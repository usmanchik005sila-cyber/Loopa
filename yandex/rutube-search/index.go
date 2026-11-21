package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
)

var videoID = regexp.MustCompile(`^[a-fA-F0-9]{32}$`)
var client = &http.Client{
	Timeout: 10 * time.Second,
	CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	},
}

const supabaseURL = "https://wnubqzwsvclvcvozibtc.supabase.co"
const requestBodyLimit = 4096
const publishableKey = "sb_publishable_yuWa66reRpb7j2q3Z4mnAA_bkGwIhpp"

func respond(w http.ResponseWriter, status int, body interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
func fail(w http.ResponseWriter, status int, message string) {
	respond(w, status, map[string]string{"message": message})
}

// Reconstructed from the owner's screenshots. Only public configuration is embedded.
func Handler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		fail(w, 405, "Используй поиск из LOOPA")
		return
	}
	token := r.Header.Get("X-Loopa-Authorization")
	credential, ok := strings.CutPrefix(token, "Bearer ")
	if !ok || credential == "" || len(token) > 8192 || strings.IndexFunc(credential, unicode.IsSpace) >= 0 {
		fail(w, 401, "Войди в аккаунт LOOPA")
		return
	}
	var input struct {
		Q    string `json:"q"`
		Page int    `json:"page"`
	}
	body := http.MaxBytesReader(w, r.Body, requestBodyLimit)
	defer body.Close()
	decoder := json.NewDecoder(body)
	err := decoder.Decode(&input)
	if err == nil {
		var extra json.RawMessage
		err = decoder.Decode(&extra)
	}
	var oversized *http.MaxBytesError
	switch {
	case errors.As(err, &oversized):
		fail(w, 413, "Запрос слишком большой")
		return
	case err != io.EOF:
		fail(w, 400, "Некорректный запрос")
		return
	}
	input.Q = strings.TrimSpace(input.Q)
	if input.Page == 0 {
		input.Page = 1
	}
	if len([]rune(input.Q)) < 2 || len([]rune(input.Q)) > 100 || input.Page < 1 || input.Page > 100 {
		fail(w, 400, "Проверь название и страницу поиска")
		return
	}
	auth, err := http.NewRequestWithContext(r.Context(), "GET", supabaseURL+"/auth/v1/user", nil)
	if err != nil {
		fail(w, 502, "Ошибка проверки входа")
		return
	}
	auth.Header.Set("Authorization", token)
	auth.Header.Set("apikey", publishableKey)
	user, err := client.Do(auth)
	if err != nil {
		fail(w, 503, "Не удалось проверить вход")
		return
	}
	user.Body.Close()
	switch user.StatusCode {
	case http.StatusOK:
	case http.StatusBadRequest, http.StatusUnauthorized, http.StatusForbidden:
		fail(w, 401, "Войди в аккаунт LOOPA")
		return
	default:
		fail(w, 503, "Не удалось проверить вход")
		return
	}
	// The same durable account quota applies even when this public URL is called directly.
	quota, err := http.NewRequestWithContext(r.Context(), "POST", supabaseURL+"/rest/v1/rpc/loopa_search_budget", strings.NewReader(`{"p_mode":"search"}`))
	if err != nil {
		fail(w, 503, "Поиск временно недоступен")
		return
	}
	quota.Header.Set("Authorization", token)
	quota.Header.Set("apikey", publishableKey)
	quota.Header.Set("Content-Type", "application/json")
	budgetResponse, err := client.Do(quota)
	if err != nil {
		fail(w, 503, "Поиск временно недоступен")
		return
	}
	var budget struct {
		Allowed *bool `json:"allowed"`
		Retry   int   `json:"retry_after"`
	}
	err = json.NewDecoder(io.LimitReader(budgetResponse.Body, 4096)).Decode(&budget)
	budgetResponse.Body.Close()
	if budgetResponse.StatusCode != 200 || err != nil || budget.Allowed == nil {
		fail(w, 503, "Поиск временно недоступен")
		return
	}
	if !*budget.Allowed {
		if budget.Retry < 1 {
			budget.Retry = 1
		}
		if budget.Retry > 60 {
			budget.Retry = 60
		}
		w.Header().Set("Retry-After", strconv.Itoa(budget.Retry))
		fail(w, 429, "Слишком много запросов. Подожди немного и попробуй снова.")
		return
	}
	params := url.Values{"query": {input.Q}, "client": {"web"}, "page": {strconv.Itoa(input.Page)}, "per_page": {"12"}}
	req, err := http.NewRequestWithContext(r.Context(), "GET", "https://rutube.ru/api/search/video/?"+params.Encode(), nil)
	if err != nil {
		fail(w, 502, "Ошибка запроса RUTUBE")
		return
	}
	req.Header.Set("Accept", "application/json")
	res, err := client.Do(req)
	if err != nil {
		fail(w, 502, "RUTUBE не ответил вовремя")
		return
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		fail(w, 502, "RUTUBE временно не принимает поиск")
		return
	}
	var data struct {
		Results *[]struct {
			ID     string `json:"id"`
			Title  string `json:"title"`
			Image  string `json:"thumbnail_url"`
			Author struct {
				Name string `json:"name"`
			} `json:"author"`
			Deleted bool `json:"is_deleted"`
			Hidden  bool `json:"is_hidden"`
			Paid    bool `json:"is_paid"`
			Locked  bool `json:"is_locked"`
		} `json:"results"`
		HasNext bool `json:"has_next"`
	}
	if json.NewDecoder(io.LimitReader(res.Body, 4<<20)).Decode(&data) != nil || data.Results == nil {
		fail(w, 502, "Не удалось прочитать каталог RUTUBE")
		return
	}
	items := []map[string]string{}
	for _, v := range *data.Results {
		if !videoID.MatchString(v.ID) || v.Title == "" || v.Deleted || v.Hidden || v.Paid || v.Locked {
			continue
		}
		image := ""
		if u, e := url.Parse(v.Image); e == nil && u.Scheme == "https" && u.Host != "" {
			image = v.Image
		}
		items = append(items, map[string]string{"title": v.Title, "author": v.Author.Name, "image": image, "url": "https://rutube.ru/video/" + v.ID + "/"})
	}
	var next interface{}
	if data.HasNext && input.Page < 100 {
		next = strconv.Itoa(input.Page + 1)
	}
	respond(w, 200, map[string]interface{}{"items": items, "next": next})
}
