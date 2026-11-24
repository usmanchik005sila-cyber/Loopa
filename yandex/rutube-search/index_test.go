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
			body = `{"results":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","title":"Video","duration":772,"thumbnail_url":"https://pic.rtbcdn.ru/cover.jpg","author":{"name":"Author"}},{"id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","title":"Private","is_hidden":true}],"has_next":true}`
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
	if w.Code != 200 || n != 1 || !strings.Contains(w.Body.String(), `"next":"2"`) ||
		!strings.Contains(w.Body.String(), `"duration":772`) || strings.Contains(w.Body.String(), "Private") {
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

func TestInlineSearchRequiresVerifiedBody(t *testing.T) {
	old := client
	defer func() { client = old }()
	const body = `{"q":"аниме","page":1,"ticket":"fixture","expires":1}`
	proof := strings.Repeat("a", 64)
	for _, verdict := range []int{http.StatusOK, http.StatusUnauthorized} {
		calls := 0
		client = &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
			if r.URL.Host == "rutube.ru" {
				calls++
				return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"results":[]}`))}, nil
			}
			forwarded, err := io.ReadAll(r.Body)
			if err != nil || string(forwarded) != body || r.Header.Get("X-Loopa-Inline-Proof") != proof ||
				r.URL.String() != supabaseURL+"/functions/v1/loopa-bot?action=verify-inline-rutube" {
				t.Fatal("signed request was not forwarded intact")
			}
			return &http.Response{StatusCode: verdict, Body: io.NopCloser(strings.NewReader(`{}`))}, nil
		})}
		req := httptest.NewRequest("POST", "https://function.test", strings.NewReader(body))
		req.Header.Set("X-Loopa-Inline-Proof", proof)
		response := httptest.NewRecorder()
		Handler(response, req)
		if response.Code != verdict || (calls == 1) != (verdict == http.StatusOK) {
			t.Fatalf("verdict %d, response %d, upstream calls %d", verdict, response.Code, calls)
		}
	}
}

func TestVideoMetadataUsesExactIDAndExistingQuota(t *testing.T) {
	const id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	old := client
	defer func() { client = old }()
	for _, allowed := range []bool{true, false} {
		upstream := 0
		client = &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
			payload := `{}`
			switch {
			case r.URL.Host == "rutube.ru":
				upstream++
				if r.URL.Path != "/api/video/"+id+"/" || r.URL.RawQuery != "" {
					t.Fatal("metadata used the wrong RUTUBE URL")
				}
				payload = `{"id":"` + id + `","title":"Космос","duration":"invalid","thumbnail_url":"https://pic.rtbcdn.ru/cover.jpg"}`
			case strings.HasSuffix(r.URL.Path, "/loopa_search_budget"):
				payload = `{"allowed":false}`
				if allowed {
					payload = `{"allowed":true}`
				}
			case r.URL.Path != "/auth/v1/user":
				t.Fatal("unexpected request", r.URL)
			}
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(payload)), Header: make(http.Header)}, nil
		})}
		request := httptest.NewRequest("POST", "https://function.test", strings.NewReader(`{"id":"`+id+`"}`))
		request.Header.Set("X-Loopa-Authorization", "Bearer fixture")
		response := httptest.NewRecorder()
		Handler(response, request)
		if allowed && (response.Code != 200 || upstream != 1 || !strings.Contains(response.Body.String(), "Космос") ||
			strings.Contains(response.Body.String(), `"duration"`)) {
			t.Fatal(response.Code, upstream, response.Body.String())
		}
		if !allowed && (response.Code != 429 || upstream != 0) {
			t.Fatal(response.Code, upstream)
		}
	}
}
