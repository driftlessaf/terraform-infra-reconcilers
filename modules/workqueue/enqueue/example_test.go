/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package enqueue_test

import (
	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/terraform-infra-reconcilers/modules/workqueue/enqueue"
)

func ExampleNewServer() {
	var wq workqueue.Interface // provide a real implementation in production
	srv := enqueue.NewServer(wq)
	_ = srv
}
