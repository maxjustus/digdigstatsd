description = "Send base process stats to datadog via statsd"
short_description = "Send base process stats to datadog via statsd"
category = "stat_aggregation"
args = {}

-- require constructor
local Statsd = require "statsd"

local statsd

function on_init()
  chisel.set_interval_s(1)
  chisel.set_filter("evt.is_io=true and (fd.type=ipv4 or fd.type=ipv6 or fd.type=file)")

  fisread = chisel.request_field("evt.is_io_read")
  fd_type = chisel.request_field("fd.type")
  fd_l4proto = chisel.request_field("fd.l4proto")
  fbytes = chisel.request_field("evt.rawarg.res")

  return true
end

function on_capture_start()
  local info = sysdig.get_machine_info()
  statsd = Statsd({
    host = "127.0.0.1",
    port = 8125, -- FIXME make this configurable
    namespace = "system.iostats." .. info.hostname
  })

  return true
end

function print_process_memory()
  local info = sysdig.get_machine_info()
  print(info.hostname)
  print(info.memory_size_bytes)

  local process = sysdig.get_thread_table()
  for pid, metadata in pairs(process) do
    print(metadata.comm)
    print("vmrss_mb: " .. metadata.vmrss_kb / 1024)
    -- print_table(metadata)
  end
end

function print_table(t)
  for k,v in pairs(t) do
    print(k)
    print(v)
  end
end

events = {}
function on_event()
  local isread = evt.field(fisread)

  local field_name = "write"
  if isread then field_name = "read" end

  local fd_type = evt.field(fd_type)
  if fd_type then
    field_name = field_name .. "." .. fd_type
  end

  local proto = evt.field(fd_l4proto)
  if proto and proto ~= "<NA>" then
    field_name = field_name .. "." .. proto
  end

  local fbytes = evt.field(fbytes)
  if not fbytes then return true end

  local fkbytes = fbytes / 1024
  if events[field_name] then
    events[field_name] = events[field_name] + fkbytes
  else
    events[field_name] = fkbytes
  end
end

function on_interval()
  -- Read/Write histogram?

  print_table(events)
  for evt, io in pairs(events) do
    statsd:gauge(evt, io)
  end
  events = {}

  return true
end
