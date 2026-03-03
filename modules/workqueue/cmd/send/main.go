/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"crypto/rand"
	"flag"
	"math/big"
	"net/url"
	"os"
	"os/signal"
	"runtime"
	"syscall"

	delegate "chainguard.dev/go-grpc-kit/pkg/options"
	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc"

	"chainguard.dev/driftlessaf/workqueue"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	httpTarget := flag.String("target", "", "The target to send work to.")
	requests := flag.Int("requests", 100000, "The number of requests to send.")
	rng := flag.Int64("range", 1000, "The range of keys to send.")
	flag.Parse()

	uri, err := url.Parse(*httpTarget)
	if err != nil {
		clog.FatalContextf(ctx, "failed to parse URI: %v", err)
	}
	target, opts := delegate.GRPCOptions(*uri)

	conn, err := grpc.NewClient(target, opts...)
	if err != nil {
		clog.FatalContextf(ctx, "failed to connect to the server: %v", err)
	}
	defer conn.Close()
	client := workqueue.NewWorkqueueServiceClient(conn)

	eg := errgroup.Group{}
	eg.SetLimit(5 * runtime.GOMAXPROCS(0))
	for i := range *requests {
		eg.Go(func() error {
			bi, err := rand.Int(rand.Reader, big.NewInt(*rng))
			if err != nil {
				return err
			}
			clog.InfoContextf(ctx, "Sending request %d: %s", i, bi.String())
			_, err = client.Process(ctx, &workqueue.ProcessRequest{Key: bi.String()})
			return err
		})
	}
	if err := eg.Wait(); err != nil {
		clog.FatalContextf(ctx, "failed to send all requests: %v", err)
	}
}
