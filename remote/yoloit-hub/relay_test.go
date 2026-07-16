package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func newRelayTestServer(t *testing.T, token string) *httptest.Server {
	t.Helper()
	store := NewStore(t.TempDir(), "test-actor")
	if err := store.Init(); err != nil {
		t.Fatalf("store init: %v", err)
	}
	srv := httptest.NewServer(newServer(store, token, "*", newRelayHub(t.TempDir())))
	t.Cleanup(srv.Close)
	return srv
}

func createDevice(t *testing.T, srv *httptest.Server, token, name string) (string, string) {
	t.Helper()
	_, body, _ := do(t, http.MethodPost, srv.URL+"/api/devices", token, map[string]any{"name": name})
	deviceID, _ := body["deviceId"].(string)
	key, _ := body["key"].(string)
	if deviceID == "" || key == "" {
		t.Fatalf("device create did not return id/key: %v", body)
	}
	return deviceID, key
}

// dialDevice connects a fake device to the relay endpoint and returns the WS.
func dialDevice(t *testing.T, srv *httptest.Server, deviceID, key string) *websocket.Conn {
	t.Helper()
	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") +
		"/api/relay/connect?deviceId=" + deviceID
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": []string{"Bearer " + key}},
	})
	if err != nil {
		t.Fatalf("device dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close(websocket.StatusNormalClosure, "test done") })
	return conn
}

func TestDeviceCreateListDelete(t *testing.T) {
	srv := newRelayTestServer(t, "tok")

	deviceID, _ := createDevice(t, srv, "tok", "macbook")

	_, body, _ := do(t, http.MethodGet, srv.URL+"/api/devices", "tok", nil)
	devices, _ := body["devices"].([]any)
	if len(devices) != 1 {
		t.Fatalf("expected 1 device, got %v", devices)
	}
	dev := devices[0].(map[string]any)
	if dev["deviceId"] != deviceID || dev["name"] != "macbook" || dev["online"] != false {
		t.Fatalf("unexpected device record: %v", dev)
	}

	// Wrong hub token is rejected by the middleware.
	resp, _, _ := do(t, http.MethodGet, srv.URL+"/api/devices", "wrong", nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 for wrong token, got %d", resp.StatusCode)
	}

	_, _, _ = do(t, http.MethodDelete, srv.URL+"/api/devices/"+deviceID, "tok", nil)
	_, body, _ = do(t, http.MethodGet, srv.URL+"/api/devices", "tok", nil)
	devices, _ = body["devices"].([]any)
	if len(devices) != 0 {
		t.Fatalf("expected 0 devices after delete, got %v", devices)
	}
}

func TestRelayConnectRequiresDeviceKey(t *testing.T) {
	srv := newRelayTestServer(t, "tok")
	deviceID, _ := createDevice(t, srv, "tok", "macbook")

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") +
		"/api/relay/connect?deviceId=" + deviceID
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, resp, err := websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": []string{"Bearer wrong-key"}},
	})
	if err == nil {
		t.Fatal("expected dial with wrong key to fail")
	}
	if resp == nil || resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %v", resp)
	}
}

func TestRelayProxyRoundTrip(t *testing.T) {
	srv := newRelayTestServer(t, "tok")
	deviceID, key := createDevice(t, srv, "tok", "macbook")

	// Device offline → 503 (using the device key for proxy access).
	resp, body, _ := do(t, http.MethodGet,
		srv.URL+"/api/devices/"+deviceID+"/api/health", key, nil)
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 for offline device, got %d: %v", resp.StatusCode, body)
	}

	// Fake device: answer relay frames with a canned response echoing the path.
	ws := dialDevice(t, srv, deviceID, key)
	go func() {
		for {
			_, data, err := ws.Read(context.Background())
			if err != nil {
				return
			}
			var frame relayFrame
			if json.Unmarshal(data, &frame) != nil || frame.ID == "" {
				continue
			}
			respBody, _ := json.Marshal(map[string]any{
				"ok": true, "echo": frame.Path, "method": frame.Method,
			})
			_ = ws.Write(context.Background(), websocket.MessageText,
				mustJSON(relayFrame{ID: frame.ID, Status: 200, Body: string(respBody)}))
		}
	}()

	// Wait until the hub reports the device online.
	deadline := time.Now().Add(5 * time.Second)
	for {
		_, list, _ := do(t, http.MethodGet, srv.URL+"/api/devices", "tok", nil)
		devices, _ := list["devices"].([]any)
		if len(devices) == 1 && devices[0].(map[string]any)["online"] == true {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("device did not come online: %v", list)
		}
		time.Sleep(50 * time.Millisecond)
	}

	resp, body, raw := do(t, http.MethodGet,
		srv.URL+"/api/devices/"+deviceID+"/api/health", key, nil)
	if resp.StatusCode != http.StatusOK || body["echo"] != "/api/health" {
		t.Fatalf("unexpected proxied response: %d %s", resp.StatusCode, raw)
	}

	// POST with a body is proxied too.
	resp, body, _ = do(t, http.MethodPost,
		srv.URL+"/api/devices/"+deviceID+"/api/boards", key,
		map[string]any{"name": "via relay"})
	if resp.StatusCode != http.StatusOK || body["method"] != "POST" {
		t.Fatalf("unexpected proxied POST response: %d %v", resp.StatusCode, body)
	}
}

func TestStaticDeviceFromConfig(t *testing.T) {
	ds := newDeviceStore(t.TempDir())
	ds.registerStatic("default", "Static device", "s3cret")

	rec := ds.get("default")
	if rec == nil || rec.Key != "s3cret" || !rec.Static {
		t.Fatalf("static device not registered: %v", rec)
	}
	// Static devices survive save/load (never persisted) and cannot be deleted.
	if ds.delete("default") {
		t.Fatal("static device must not be deletable")
	}
}

func mustJSON(v any) []byte {
	data, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return data
}
