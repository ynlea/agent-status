package server

import (
	"encoding/json"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/ynlea/agent-status/pkg/apitypes"
)

// Hub broadcasts WS events to app clients and pushes commands to monitors.
type Hub struct {
	mu       sync.Mutex
	clients  map[*websocket.Conn]struct{}
	monitors map[string]*websocket.Conn // machine_id -> conn
	// reverse index for cleanup
	monitorOwner map[*websocket.Conn]string
}

func NewHub() *Hub {
	return &Hub{
		clients:      make(map[*websocket.Conn]struct{}),
		monitors:     make(map[string]*websocket.Conn),
		monitorOwner: make(map[*websocket.Conn]string),
	}
}

func (h *Hub) Add(c *websocket.Conn) {
	h.mu.Lock()
	h.clients[c] = struct{}{}
	h.mu.Unlock()
}

func (h *Hub) Remove(c *websocket.Conn) {
	h.mu.Lock()
	delete(h.clients, c)
	if mid, ok := h.monitorOwner[c]; ok {
		if h.monitors[mid] == c {
			delete(h.monitors, mid)
		}
		delete(h.monitorOwner, c)
	}
	h.mu.Unlock()
	_ = c.Close()
}

// SetMonitor registers a monitor websocket for machineID (replaces previous).
func (h *Hub) SetMonitor(machineID string, c *websocket.Conn) {
	if machineID == "" || c == nil {
		return
	}
	h.mu.Lock()
	if old, ok := h.monitors[machineID]; ok && old != c {
		delete(h.monitorOwner, old)
		_ = old.Close()
	}
	h.monitors[machineID] = c
	h.monitorOwner[c] = machineID
	h.mu.Unlock()
}

// PushToMonitor sends an event to the monitor for machineID.
// Returns false if no live monitor connection.
func (h *Hub) PushToMonitor(machineID string, ev apitypes.WSEvent) bool {
	data, err := json.Marshal(ev)
	if err != nil {
		return false
	}
	h.mu.Lock()
	c, ok := h.monitors[machineID]
	h.mu.Unlock()
	if !ok || c == nil {
		return false
	}
	if err := c.WriteMessage(websocket.TextMessage, data); err != nil {
		h.Remove(c)
		return false
	}
	return true
}

func (h *Hub) Broadcast(ev apitypes.WSEvent) {
	data, err := json.Marshal(ev)
	if err != nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if err := c.WriteMessage(websocket.TextMessage, data); err != nil {
			_ = c.Close()
			delete(h.clients, c)
		}
	}
}
