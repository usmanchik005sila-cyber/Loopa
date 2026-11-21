package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func run(t *testing.T, auth string, quotaStatus int, quotaBody string) (*httptest.ResponseRecorder, int) {
	t.Helper()
	old := client
	defer func() { client = old }()
	upstream := 0
	client = &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		status, body := 200, `{}`
		switch r.URL.Host {
		case "wnubqzwsvclvcvozibtc.supabase.co":
			if r.Header.Get("Authorization") != "Bearer fixture" {
				t.Fatal("user token not forwarded")
			}
			if strings.Contains(r.URL.Path, "loopa_search_budget") {
				status, body = quotaStatus, quotaBody
			}
		case "rutube.ru":
			upstream++
			body = `{"results":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","title":"Video","thumbnail_url":"https://pic.rtbcdn.ru/cover.jpg","author":{"name":"Author"}},{"id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","title":"Private","is_hidden":true}],"has_next":true}`
			if r.URL.Query().Get("per_page") != "12" {
				t.Fatal("pagination changed")
			}
		default:
			t.Fatal("unexpected upstream")
		}
		return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}, nil
	})}
	req := httptest.NewRequest("POST", "https://function.test", strings.NewReader(`{"q":"nature","page":1}`))
	req.Header.Set("X-Loopa-Authorization", auth)
	w := httptest.NewRecorder()
	Handler(w, req)
	return w, upstream
}
func TestSearch(t *testing.T) {
	w, n := run(t, "Bearer fixture", 200, `{"allowed":true}`)
	if w.Code != 200 || n != 1 || !strings.Contains(w.Body.String(), `"next":"2"`) || strings.Contains(w.Body.String(), "Private") {
		t.Fatal(w.Code, w.Body.String(), n)
	}
}
func TestDirectQuotaDenied(t *testing.T) {
	w, n := run(t, "Bearer fixture", 200, `{"allowed":false,"retry_after":3}`)
	if w.Code != 429 || n != 0 || w.Header().Get("Retry-After") != "3" {
		t.Fatal(w.Code, n)
	}
}
func TestQuotaFailsClosed(t *testing.T) {
	for _, body := range []string{`{}`, `broken`, `{"allowed":true}`} {
		status := 200
		if strings.Contains(body, "true") {
			status = 500
		}
		w, n := run(t, "Bearer fixture", status, body)
		if w.Code != 503 || n != 0 {
			t.Fatal(w.Code, n)
		}
	}
}
func TestMissingAuth(t *testing.T) {
	w, n := run(t, "", 200, `{"allowed":true}`)
	if w.Code != 401 || n != 0 {
		t.Fatal(w.Code, n)
	}
}

func TestInvalidInputStopsBeforeNetwork(t *testing.T) {
	old := client
	t.Cleanup(func() { client = old })
	client = &http.Client{Transport: transport(func(*http.Request) (*http.Response, error) {
		t.Fatal("validation failure reached an external service")
		return nil, nil
	})}
	for _, fixture := range []struct {
		body string
		want int
	}{
		{`{"q":"nature"} {}`, http.StatusBadRequest},
		{`{"q":"nature"}` + strings.Repeat(" ", requestBodyLimit), http.StatusRequestEntityTooLarge},
		{`{"q":"nature","page":101}`, http.StatusBadRequest},
	} {
		req := httptest.NewRequest("POST", "https://function.test", strings.NewReader(fixture.body))
		req.Header.Set("X-Loopa-Authorization", "Bearer fixture")
		w := httptest.NewRecorder()
		Handler(w, req)
		if w.Code != fixture.want {
			t.Errorf("status %d, want %d", w.Code, fixture.want)
		}
	}
}

func TestAuthOutageStopsBeforeQuota(t *testing.T) {
	old := client
	t.Cleanup(func() { client = old })
	client = &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		if r.URL.Path != "/auth/v1/user" {
			t.Fatal("auth outage reached quota or RUTUBE")
		}
		return &http.Response{StatusCode: http.StatusServiceUnavailable, Body: http.NoBody, Header: make(http.Header)}, nil
	})}
	req := httptest.NewRequest("POST", "https://function.test", strings.NewReader(`{"q":"nature"}`))
	req.Header.Set("X-Loopa-Authorization", "Bearer fixture")
	w := httptest.NewRecorder()
	Handler(w, req)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("status %d, want 503", w.Code)
	}
}
