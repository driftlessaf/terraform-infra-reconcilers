// module.dispatcher-service now has count = (dispatcher_service_enabled ? 1 : 0).
// Existing deployments have state at the bare address; move to [0].
moved {
  from = module.dispatcher-service
  to   = module.dispatcher-service[0]
}
