local DEFAULT_PILOT_NAME = "Rotorflight"
local DEFAULT_BATTERY_ALERT_PCT = 25
local DEFAULT_BATTERY_ALERT_INTERVAL = 10
local CONFIG_FILE = "/WIDGETS/DBK_TX16KMK3_config.json"
local DEBUG_FILE = "/WIDGETS/DBK_TX16KMK3/logs/System/config_debug.txt"

local function decode_json_string(value)
    if not value then
        return ""
    end

    value = string.gsub(value, '\\"', '"')
    value = string.gsub(value, "\\\\", "\\")
    value = string.gsub(value, "\\n", "\n")
    value = string.gsub(value, "\\r", "\r")
    value = string.gsub(value, "\\t", "\t")
    return value
end

local function get_json_string_value(content, key)
    local key_pattern = '"' .. key .. '"%s*:%s*"'
    local start_pos, end_pos = string.find(content, key_pattern)
    if not start_pos then
        return nil
    end

    local i = end_pos + 1
    local chars = {}
    local escaped = false

    while i <= #content do
        local ch = string.sub(content, i, i)
        if escaped then
            chars[#chars + 1] = "\\" .. ch
            escaped = false
        elseif ch == "\\" then
            escaped = true
        elseif ch == '"' then
            break
        else
            chars[#chars + 1] = ch
        end
        i = i + 1
    end

    local value = table.concat(chars)
    value = decode_json_string(value)
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    if value == "" then
        return nil
    end

    return value
end

local function get_json_number_value(content, key)
    local value = string.match(content, '"' .. key .. '"%s*:%s*(-?%d+%.?%d*)')
    if not value then
        return nil
    end

    return tonumber(value)
end

local function build_default_widget_config_json()
    return string.format(
        '{\n  "pilot_name": "%s",\n  "battery_alert_pct": %d,\n  "battery_alert_interval": %d\n}\n',
        DEFAULT_PILOT_NAME,
        DEFAULT_BATTERY_ALERT_PCT,
        DEFAULT_BATTERY_ALERT_INTERVAL
    )
end

local function get_default_widget_config()
    return {
        pilot_name = DEFAULT_PILOT_NAME,
        battery_alert_pct = DEFAULT_BATTERY_ALERT_PCT,
        battery_alert_interval = DEFAULT_BATTERY_ALERT_INTERVAL
    }
end

local function write_config_debug_log(stage, content, config)
    local debug_file = io.open(DEBUG_FILE, "w")
    if not debug_file then
        return
    end

    io.write(debug_file, "stage=" .. tostring(stage) .. "\n")
    io.write(debug_file, "config_file=" .. CONFIG_FILE .. "\n")

    local file_info = fstat(CONFIG_FILE)
    if file_info then
        io.write(debug_file, "config_size=" .. tostring(file_info.size) .. "\n")
    else
        io.write(debug_file, "config_size=nil\n")
    end

    io.write(debug_file, "raw_begin\n")
    io.write(debug_file, content or "")
    if not content or content == "" or string.sub(content, -1) ~= "\n" then
        io.write(debug_file, "\n")
    end
    io.write(debug_file, "raw_end\n")

    if config then
        io.write(debug_file, "pilot_name=" .. tostring(config.pilot_name) .. "\n")
        io.write(debug_file, "battery_alert_pct=" .. tostring(config.battery_alert_pct) .. "\n")
        io.write(debug_file, "battery_alert_interval=" .. tostring(config.battery_alert_interval) .. "\n")
    end

    io.close(debug_file)
end

local function ensure_widget_config_file()
    local file_info = fstat(CONFIG_FILE)
    if file_info and file_info.size > 0 then
        return
    end

    local config_file = io.open(CONFIG_FILE, "w")
    if not config_file then
        return
    end

    io.write(config_file, build_default_widget_config_json())
    io.close(config_file)
end

local function load_widget_config(write_debug)
    ensure_widget_config_file()
    local file_info = fstat(CONFIG_FILE)
    if not file_info or file_info.size <= 0 then
        local default_config = get_default_widget_config()
        if write_debug then write_config_debug_log("missing_or_empty", "", default_config) end
        return default_config
    end

    local config_file = io.open(CONFIG_FILE, "r")
    if not config_file then
        local default_config = get_default_widget_config()
        if write_debug then write_config_debug_log("open_failed", "", default_config) end
        return default_config
    end

    local content = io.read(config_file, file_info.size) or ""
    io.close(config_file)

    local pilot_name = get_json_string_value(content, "pilot_name") or DEFAULT_PILOT_NAME
    local battery_alert_pct = get_json_number_value(content, "battery_alert_pct") or DEFAULT_BATTERY_ALERT_PCT
    local battery_alert_interval = get_json_number_value(content, "battery_alert_interval") or DEFAULT_BATTERY_ALERT_INTERVAL

    if battery_alert_pct < 0 then
        battery_alert_pct = 0
    elseif battery_alert_pct > 100 then
        battery_alert_pct = 100
    end

    battery_alert_pct = math.floor(battery_alert_pct)

    if battery_alert_interval < 1 then
        battery_alert_interval = 1
    end

    local parsed_config = {
        pilot_name = pilot_name,
        battery_alert_pct = math.floor(battery_alert_pct),
        battery_alert_interval = math.floor(battery_alert_interval)
    }

    if write_debug then write_config_debug_log("parsed", content, parsed_config) end
    return parsed_config
end

return {
    defaults = get_default_widget_config(),
    load = load_widget_config
}
