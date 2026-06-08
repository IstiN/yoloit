package server

import (
	"testing"

	"yoloitd/session"
)

func TestCreateAndGet(t *testing.T) {
	s := New()

	req := &session.CreateRequest{
		ID:      "test-1",
		Command: "echo hello",
		Cols:    80,
		Rows:    24,
	}

	sess, existing, err := s.Create(req)
	if err != nil {
		t.Fatalf("create failed: %v", err)
	}
	if existing {
		t.Fatal("expected new session")
	}
	if sess.ID() != "test-1" {
		t.Fatalf("unexpected id: %s", sess.ID())
	}

	got, ok := s.Get("test-1")
	if !ok {
		t.Fatal("expected session to exist")
	}
	if got.ID() != "test-1" {
		t.Fatalf("unexpected id: %s", got.ID())
	}
}

func TestCreateDuplicate(t *testing.T) {
	s := New()

	req := &session.CreateRequest{
		ID:      "dup",
		Command: "sleep 10",
		Cols:    80,
		Rows:    24,
	}

	_, _, err := s.Create(req)
	if err != nil {
		t.Fatalf("first create failed: %v", err)
	}

	_, existing, err := s.Create(req)
	if err != nil {
		t.Fatalf("second create failed: %v", err)
	}
	if !existing {
		t.Fatal("expected existing=true on duplicate")
	}
}

func TestGetMissing(t *testing.T) {
	s := New()
	_, ok := s.Get("missing")
	if ok {
		t.Fatal("expected session not found")
	}
}
