package server

import (
	"fmt"
	"sync"
	"time"

	"yoloitd/session"
)

// Server holds all active terminal sessions.
type Server struct {
	mu       sync.RWMutex
	sessions map[string]*session.Session
}

// New creates a new server instance and starts background cleanup.
func New() *Server {
	s := &Server{
		sessions: make(map[string]*session.Session),
	}
	go s.cleanupLoop()
	return s
}

// cleanupLoop removes dead sessions every 30 seconds.
func (s *Server) cleanupLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		s.mu.Lock()
		for id, sess := range s.sessions {
			if !sess.Alive() {
				delete(s.sessions, id)
			}
		}
		s.mu.Unlock()
	}
}

// Create starts a new session or returns an existing alive one.
func (s *Server) Create(req *session.CreateRequest) (*session.Session, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if req.ID == "" {
		return nil, false, fmt.Errorf("missing session id")
	}

	if existing, ok := s.sessions[req.ID]; ok && existing.Alive() {
		return existing, true, nil
	}

	sess, err := session.New(req)
	if err != nil {
		return nil, false, err
	}

	s.sessions[req.ID] = sess
	return sess, false, nil
}

// Get returns a session by id.
func (s *Server) Get(id string) (*session.Session, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	sess, ok := s.sessions[id]
	return sess, ok
}

// All returns a snapshot of all sessions.
func (s *Server) All() []*session.Session {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*session.Session, 0, len(s.sessions))
	for _, sess := range s.sessions {
		result = append(result, sess)
	}
	return result
}

// KillAll terminates every session.
func (s *Server) KillAll() {
	s.mu.RLock()
	sessions := make([]*session.Session, 0, len(s.sessions))
	for _, sess := range s.sessions {
		sessions = append(sessions, sess)
	}
	s.mu.RUnlock()

	for _, sess := range sessions {
		sess.Kill()
	}
}
