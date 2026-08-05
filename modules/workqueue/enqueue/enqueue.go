/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// Package enqueue serves the workqueue gRPC service by enqueuing keys into
// a backing workqueue.
package enqueue

import (
	"context"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"chainguard.dev/driftlessaf/workqueue"
)

// Server implements the workqueue gRPC service by enqueuing each processed
// key into the backing workqueue. A request's DelaySeconds defers the key's
// eligibility by setting its NotBefore.
type Server struct {
	workqueue.UnimplementedWorkqueueServiceServer

	wq workqueue.Interface
}

// NewServer returns a Server enqueuing into wq.
func NewServer(wq workqueue.Interface) *Server {
	return &Server{wq: wq}
}

// Process implements workqueue.WorkqueueServiceServer.
func (s *Server) Process(ctx context.Context, req *workqueue.ProcessRequest) (*workqueue.ProcessResponse, error) {
	var nbf time.Time
	if req.DelaySeconds > 0 {
		nbf = time.Now().UTC().Add(time.Duration(req.DelaySeconds) * time.Second)
	}
	if err := s.wq.Queue(ctx, req.Key, workqueue.Options{
		Priority:  req.Priority,
		NotBefore: nbf,
	}); err != nil {
		return nil, status.Errorf(codes.Internal, "Queue() = %v", err)
	}
	return &workqueue.ProcessResponse{}, nil
}

// GetKeyState implements workqueue.WorkqueueServiceServer.
func (s *Server) GetKeyState(ctx context.Context, req *workqueue.GetKeyStateRequest) (*workqueue.KeyState, error) {
	return s.wq.Get(ctx, req.Key)
}
