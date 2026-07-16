package main

// Relay: devices (Macs running YoLoIT) dial out to the hub over a WebSocket
// and register under a device key. User clients (mobile, browser) then reach
// the device's boards through /api/devices/:id/* — the hub proxies each HTTP
// request over the device's outbound WS connection, so the device never needs
// inbound connectivity (NAT / blocked LAN).
//
// Wire protocol (JSON text frames):
//   hub → device: {"id":"...","method":"GET","path":"/api/boards","query":"...","body":"..."}
//   device → hub: {"id":"...","status":200,"body":"...","error":"..."}

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
)

const (
	relayRequestTimeout = 55 * time.Second
	relayPingInterval   = 30 * time.Second
	relayMaxBody        = 32 << 20
)

// ── Device key store ─────────────────────────────────────────────────────────

type deviceRecord struct {
	DeviceID  string `json:"deviceId"`
	Name      string `json:"name"`
	Key       string `json:"key"`
	CreatedAt string `json:"createdAt"`
	Static    bool   `json:"static,omitempty"`
}

type deviceStore struct {
	path    string
	mu      sync.Mutex
	devices map[string]*deviceRecord
}

func newDeviceStore(dataDir string) *deviceStore {
	ds := &deviceStore{
		path:    filepath.Join(dataDir, "devices.json"),
		devices: map[string]*deviceRecord{},
	}
	data, err := os.ReadFile(ds.path)
	if err == nil {
		var list []*deviceRecord
		if json.Unmarshal(data, &list) == nil {
			for _, rec := range list {
				if rec != nil && rec.DeviceID != "" {
					ds.devices[rec.DeviceID] = rec
				}
			}
		}
	}
	return ds
}

func (ds *deviceStore) saveLocked() {
	list := make([]*deviceRecord, 0, len(ds.devices))
	for _, rec := range ds.devices {
		if !rec.Static {
			list = append(list, rec)
		}
	}
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(ds.path, data, 0o600)
}

func (ds *deviceStore) create(name string) *deviceRecord {
	ds.mu.Lock()
	defer ds.mu.Unlock()
	rec := &deviceRecord{
		DeviceID:  "dev-" + randomHex(8),
		Name:      name,
		Key:       randomHex(24),
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}
	ds.devices[rec.DeviceID] = rec
	ds.saveLocked()
	return rec
}

func (ds *deviceStore) get(id string) *deviceRecord {
	ds.mu.Lock()
	defer ds.mu.Unlock()
	return ds.devices[id]
}

func (ds *deviceStore) list() []*deviceRecord {
	ds.mu.Lock()
	defer ds.mu.Unlock()
	out := make([]*deviceRecord, 0, len(ds.devices))
	for _, rec := range ds.devices {
		out = append(out, rec)
	}
	return out
}

func (ds *deviceStore) delete(id string) bool {
	ds.mu.Lock()
	defer ds.mu.Unlock()
	rec, ok := ds.devices[id]
	if !ok || rec.Static {
		return false
	}
	delete(ds.devices, id)
	ds.saveLocked()
	return true
}

// registerStatic adds (or replaces) an in-memory, env-backed device record
// that survives restarts without admin calls. Static records are never
// persisted or deleted via the API.
func (ds *deviceStore) registerStatic(id, name, key string) {
	ds.mu.Lock()
	defer ds.mu.Unlock()
	ds.devices[id] = &deviceRecord{
		DeviceID:  id,
		Name:      name,
		Key:       key,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
		Static:    true,
	}
}

func randomHex(n int) string {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return hex.EncodeToString(buf)
}

// ── Relay connection ─────────────────────────────────────────────────────────

type relayFrame struct {
	ID     string `json:"id"`
	Method string `json:"method,omitempty"`
	Path   string `json:"path,omitempty"`
	Query  string `json:"query,omitempty"`
	Body   string `json:"body,omitempty"`
	Status int    `json:"status,omitempty"`
	Error  string `json:"error,omitempty"`
}

type relayConn struct {
	ws      *websocket.Conn
	writeMu sync.Mutex
	pendMu  sync.Mutex
	pending map[string]chan relayFrame
	done    chan struct{}
}

func newRelayConn(ws *websocket.Conn) *relayConn {
	return &relayConn{
		ws:      ws,
		pending: map[string]chan relayFrame{},
		done:    make(chan struct{}),
	}
}

func (c *relayConn) send(frame relayFrame) error {
	data, err := json.Marshal(frame)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	return c.ws.Write(ctx, websocket.MessageText, data)
}

// request forwards one HTTP request to the device and waits for its response.
func (c *relayConn) request(frame relayFrame) (relayFrame, error) {
	ch := make(chan relayFrame, 1)
	c.pendMu.Lock()
	select {
	case <-c.done:
		c.pendMu.Unlock()
		return relayFrame{}, fmt.Errorf("connection closed")
	default:
	}
	c.pending[frame.ID] = ch
	c.pendMu.Unlock()
	defer func() {
		c.pendMu.Lock()
		delete(c.pending, frame.ID)
		c.pendMu.Unlock()
	}()

	if err := c.send(frame); err != nil {
		return relayFrame{}, err
	}
	select {
	case resp := <-ch:
		return resp, nil
	case <-c.done:
		return relayFrame{}, fmt.Errorf("connection closed")
	case <-time.After(relayRequestTimeout):
		return relayFrame{}, fmt.Errorf("device response timeout")
	}
}

func (c *relayConn) readLoop(onClose func()) {
	defer onClose()
	for {
		_, data, err := c.ws.Read(context.Background())
		if err != nil {
			return
		}
		var frame relayFrame
		if json.Unmarshal(data, &frame) != nil || frame.ID == "" {
			continue
		}
		c.pendMu.Lock()
		ch := c.pending[frame.ID]
		c.pendMu.Unlock()
		if ch != nil {
			select {
			case ch <- frame:
			default:
			}
		}
	}
}

func (c *relayConn) pingLoop() {
	ticker := time.NewTicker(relayPingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-c.done:
			return
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			err := c.ws.Ping(ctx)
			cancel()
			if err != nil {
				_ = c.ws.Close(websocket.StatusInternalError, "ping failed")
				return
			}
		}
	}
}

func (c *relayConn) failPending() {
	c.pendMu.Lock()
	defer c.pendMu.Unlock()
	select {
	case <-c.done:
	default:
		close(c.done)
	}
	for id, ch := range c.pending {
		close(ch)
		delete(c.pending, id)
	}
}

// ── Relay hub (registry + handlers) ──────────────────────────────────────────

type relayHub struct {
	devices *deviceStore
	mu      sync.RWMutex
	online  map[string]*relayConn
}

func newRelayHub(dataDir string) *relayHub {
	return &relayHub{
		devices: newDeviceStore(dataDir),
		online:  map[string]*relayConn{},
	}
}

func (h *relayHub) setOnline(deviceID string, conn *relayConn) {
	h.mu.Lock()
	prev := h.online[deviceID]
	h.online[deviceID] = conn
	h.mu.Unlock()
	if prev != nil {
		prev.failPending()
		_ = prev.ws.Close(websocket.StatusNormalClosure, "replaced by a new connection")
	}
	log.Printf("[yoloit-hub] relay device connected: %s", deviceID)
}

func (h *relayHub) setOffline(deviceID string, conn *relayConn) {
	h.mu.Lock()
	if h.online[deviceID] == conn {
		delete(h.online, deviceID)
	}
	h.mu.Unlock()
	conn.failPending()
	log.Printf("[yoloit-hub] relay device disconnected: %s", deviceID)
}

func (h *relayHub) connFor(deviceID string) *relayConn {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.online[deviceID]
}

func (h *relayHub) isOnline(deviceID string) bool {
	return h.connFor(deviceID) != nil
}

// ── HTTP handlers (methods on *server) ───────────────────────────────────────

// handleDevicesRoot serves GET /api/devices (list with online status) and
// POST /api/devices (create device key; admin = hub token, already enforced
// by the auth middleware).
func (s *server) handleDevicesRoot(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		type deviceInfo struct {
			DeviceID  string `json:"deviceId"`
			Name      string `json:"name"`
			Online    bool   `json:"online"`
			CreatedAt string `json:"createdAt"`
			BaseURL   string `json:"baseUrl"`
		}
		out := make([]deviceInfo, 0)
		for _, rec := range s.relay.devices.list() {
			out = append(out, deviceInfo{
				DeviceID:  rec.DeviceID,
				Name:      rec.Name,
				Online:    s.relay.isOnline(rec.DeviceID),
				CreatedAt: rec.CreatedAt,
				BaseURL:   "/api/devices/" + rec.DeviceID,
			})
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "devices": out})
	case http.MethodPost:
		body, err := readJSONBody(r)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "invalid JSON body"})
			return
		}
		name, _ := body["name"].(string)
		rec := s.relay.devices.create(name)
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":       true,
			"deviceId": rec.DeviceID,
			"name":     rec.Name,
			"key":      rec.Key,
			"baseUrl":  "/api/devices/" + rec.DeviceID,
		})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"ok": false, "error": "method not allowed"})
	}
}

// handleDevicesSubtree serves DELETE /api/devices/:id and proxies everything
// else under /api/devices/:id/ to the connected device.
func (s *server) handleDevicesSubtree(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/devices/")
	deviceID := rest
	proxyPath := ""
	if idx := strings.Index(rest, "/"); idx >= 0 {
		deviceID = rest[:idx]
		proxyPath = rest[idx:]
	}

	rec := s.relay.devices.get(deviceID)
	if rec == nil {
		notFound(w)
		return
	}

	// DELETE /api/devices/:id is protected by the hub token in the auth
	// middleware; device-key auth is only required for proxying to the device.
	isProxy := proxyPath != "" || r.Method != http.MethodDelete
	if isProxy {
		key := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if key == "" {
			key = r.URL.Query().Get("key")
		}
		if subtle.ConstantTimeCompare([]byte(key), []byte(rec.Key)) != 1 {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"ok": false, "error": "unauthorized"})
			return
		}
	}

	if proxyPath == "" {
		if r.Method == http.MethodDelete {
			if !s.relay.devices.delete(deviceID) {
				writeJSON(w, http.StatusConflict, map[string]any{"ok": false, "error": "static device cannot be deleted"})
				return
			}
			if conn := s.relay.connFor(deviceID); conn != nil {
				conn.failPending()
				_ = conn.ws.Close(websocket.StatusNormalClosure, "device revoked")
			}
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
			return
		}
		notFound(w)
		return
	}

	conn := s.relay.connFor(deviceID)
	if conn == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"ok":    false,
			"error": "device offline",
		})
		return
	}

	bodyBytes, err := io.ReadAll(io.LimitReader(r.Body, relayMaxBody))
	if err != nil {
		fail(w, err)
		return
	}
	resp, err := conn.request(relayFrame{
		ID:     "req-" + randomHex(12),
		Method: r.Method,
		Path:   proxyPath,
		Query:  r.URL.RawQuery,
		Body:   string(bodyBytes),
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	if resp.Error != "" {
		writeJSON(w, http.StatusBadGateway, map[string]any{"ok": false, "error": resp.Error})
		return
	}
	status := resp.Status
	if status == 0 {
		status = http.StatusOK
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = io.WriteString(w, resp.Body)
}

// handleRelayConnect upgrades GET /api/relay/connect?deviceId=X to a
// WebSocket after authenticating with the device key (Bearer or ?key=).
// This endpoint is exempt from the hub-token auth middleware.
func (s *server) handleRelayConnect(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("deviceId")
	rec := s.relay.devices.get(deviceID)
	if rec == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"ok": false, "error": "unknown device"})
		return
	}
	key := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if key == "" {
		key = r.URL.Query().Get("key")
	}
	if subtle.ConstantTimeCompare([]byte(key), []byte(rec.Key)) != 1 {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"ok": false, "error": "invalid device key"})
		return
	}

	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		OriginPatterns: []string{"*"},
	})
	if err != nil {
		log.Printf("[yoloit-hub] relay upgrade failed for %s: %v", deviceID, err)
		return
	}
	ws.SetReadLimit(relayMaxBody)

	conn := newRelayConn(ws)
	s.relay.setOnline(deviceID, conn)
	go conn.pingLoop()
	conn.readLoop(func() { s.relay.setOffline(deviceID, conn) })
}
