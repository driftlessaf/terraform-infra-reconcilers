/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/sethvargo/go-envconfig"

	"chainguard.dev/driftlessaf/workqueue"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Port             int    `env:"PORT,default=8080"`
	WorkqueueService string `env:"WORKQUEUE_SERVICE,required"`
	ExtensionKey     string `env:"EXTENSION_KEY,required"`
	Priority         int64  `env:"PRIORITY,default=0"`
}{})

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	clog.InfoContext(ctx, "Starting CloudEvents to Workqueue subscriber",
		"port", env.Port,
		"workqueue_service", env.WorkqueueService,
		"extension_key", env.ExtensionKey,
	)

	// Create workqueue client
	queueClient, err := workqueue.NewWorkqueueClient(ctx, env.WorkqueueService)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create workqueue client: %v", err)
	}
	defer queueClient.Close()

	// Create CloudEvents client
	p, err := cloudevents.NewHTTP(
		cloudevents.WithPort(env.Port),
		cloudevents.WithPath("/"),
	)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create CloudEvents HTTP transport: %v", err)
	}

	c, err := cloudevents.NewClient(p)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create CloudEvents client: %v", err)
	}

	// Create handler
	handler := &eventHandler{
		queueClient:  queueClient,
		extensionKey: env.ExtensionKey,
		priority:     env.Priority,
	}

	// Start receiving events
	clog.InfoContext(ctx, "Ready to receive CloudEvents")
	if err := c.StartReceiver(ctx, handler.handleEvent); err != nil {
		clog.FatalContextf(ctx, "Failed to start CloudEvents receiver: %v", err)
	}
}

type eventHandler struct {
	queueClient  workqueue.Client
	extensionKey string
	priority     int64
}

func (h *eventHandler) handleEvent(ctx context.Context, event cloudevents.Event) error {
	ctx = clog.WithValues(ctx,
		"event_id", event.ID(),
		"event_type", event.Type(),
		"event_source", event.Source(),
		"event_subject", event.Subject(),
	)

	clog.DebugContext(ctx, "Received CloudEvent")

	// Extract the workqueue key from the specified extension
	extensions := event.Extensions()
	keyValue, ok := extensions[h.extensionKey]
	if !ok {
		clog.WarnContext(ctx, "Extension key not found in event, skipping",
			"extension_key", h.extensionKey)
		// Return success to acknowledge the event (we don't want to retry)
		return nil
	}

	key, ok := keyValue.(string)
	if !ok {
		clog.ErrorContext(ctx, "Extension value is not a string",
			"extension_key", h.extensionKey,
			"extension_value", keyValue,
			"extension_type", fmt.Sprintf("%T", keyValue),
		)
		// Return success to acknowledge the event (we don't want to retry)
		return nil
	}

	if key == "" {
		clog.WarnContext(ctx, "Extension value is empty, skipping",
			"extension_key", h.extensionKey)
		// Return success to acknowledge the event (we don't want to retry)
		return nil
	}

	ctx = clog.WithValues(ctx, "workqueue_key", key)

	// Queue the work item
	_, err := h.queueClient.Process(ctx, &workqueue.ProcessRequest{
		Key:      key,
		Priority: h.priority,
	})
	if err != nil {
		clog.ErrorContextf(ctx, "Failed to queue work item: %v", err)
		// Return error to trigger pubsub retry
		return fmt.Errorf("failed to queue work item: %w", err)
	}

	clog.InfoContext(ctx, "Successfully queued work item")
	return nil
}

// Health check endpoint (CloudEvents client will set this up at /health/ready)
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write([]byte("OK\n")); err != nil {
		clog.ErrorContextf(r.Context(), "Failed to write health response: %v", err)
	}
}

func init() {
	// Add a health check endpoint
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" && r.Method == http.MethodGet {
			healthHandler(w, r)
			return
		}
		// Let CloudEvents handle other requests
		http.NotFound(w, r)
	})
}
