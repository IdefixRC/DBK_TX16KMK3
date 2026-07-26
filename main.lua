local NAME = "DBK_TX16KMK3"
local VERSION = "v1.0.5"
local WIDGET_DIR = "DBK_TX16KMK3"
local WIDGET_ROOT = "/WIDGETS/" .. WIDGET_DIR
local IMAGE_ROOT = WIDGET_ROOT .. "/image"
local MODEL_IMAGE_ROOT = "/IMAGES"
local AUDIO_ROOT = WIDGET_ROOT .. "/audio"
local LOG_ROOT = WIDGET_ROOT .. "/logs"
local SYSTEM_LOG_ROOT = LOG_ROOT .. "/System"
local config_loader = loadScript(WIDGET_ROOT .. "/config.lua")
local widget_config = config_loader and config_loader() or {
    defaults = {
        pilot_name = "Rotorflight",
        battery_alert_pct = 25,
        battery_alert_interval = 10
    },
    load = function()
        return {
            pilot_name = "Rotorflight",
            battery_alert_pct = 25,
            battery_alert_interval = 10
        }
    end
}
local DEFAULT_PILOT_NAME = widget_config.defaults.pilot_name
local DEFAULT_BATTERY_ALERT_PCT = widget_config.defaults.battery_alert_pct
local DEFAULT_BATTERY_ALERT_INTERVAL = widget_config.defaults.battery_alert_interval
-- Telemetry sensor order
--  1:Vbat  2:Curr  3:Hspd  4:Capa  5:Bat%  6:Tesc  7:Tmcu  8:1RSS  9:2RSS
-- 10:RQly 11:Thr  12:Vbec 13:ARM  14:Gov  15:Vcel 16:Tmcu 17:PID# 18:ARMD
local crsf_field = { "Vbat", "Curr", "Hspd", "Capa", "Bat%", "Tesc", "Tmcu", "1RSS", "2RSS", "RQly", "Thr", "Vbec", "ARM", "Gov", "Vcel","Tmcu","PID#","ARMD" }
local TELE_ITEMS = #crsf_field
local LOG_INFO_LEN = 22
local LOG_DATA_LEN = 115
local value_min_max = {}
local field_id = {}
local bank_info = { current = 1, name = "Bank 1" }

-- Immutable drawing lookup tables. Keeping these outside refresh-time functions
-- avoids rebuilding short-lived Lua tables on every frame.
local LED_TRAIL_COLORS = {
    { 255, 0, 0 }, { 224, 0, 0 }, { 176, 0, 0 },
    { 128, 0, 0 }, { 80, 0, 0 }, { 48, 0, 0 }
}
local GAUGE_SCALE_STEPS = { 0, 20, 40, 60, 80, 100 }
local GOVERNOR_STATE_NAMES = {
    [0] = "OFF", [1] = "IDLE", [2] = "SPOOLUP", [3] = "RECOVERY",
    [4] = "ACTIVE", [5] = "THR-OFF", [6] = "LOST-HS", [7] = "AUTOROT",
    [8] = "BAILOUT", [100] = "DISABLED", [101] = "DISARMED"
}
local PROFILE_AUDIO_FILES = {
    [1] = "profile/1.wav", [2] = "profile/2.wav", [3] = "profile/3.wav",
    [4] = "profile/4.wav", [5] = "profile/5.wav", [6] = "profile/6.wav"
}
local DIGIT_SEGMENTS = {
    [0] = {1,1,1,1,1,1,0}, [1] = {0,1,1,0,0,0,0},
    [2] = {1,1,0,1,1,0,1}, [3] = {1,1,1,1,0,0,1},
    [4] = {0,1,1,0,0,1,1}, [5] = {1,0,1,1,0,1,1},
    [6] = {1,0,1,1,1,1,1}, [7] = {1,1,1,0,0,0,0},
    [8] = {1,1,1,1,1,1,1}, [9] = {1,1,1,1,0,1,1}
}

-- Bitmap assets
local tg_pic_obj
local bg_pic_obj
local runtime_cache = {
    model_name = "",
    safe_model_name = "",
    log_date_stamp = "",
    pic_path = "",
    pilot_name = DEFAULT_PILOT_NAME,
    battery_alert_pct = DEFAULT_BATTERY_ALERT_PCT,
    battery_alert_interval = DEFAULT_BATTERY_ALERT_INTERVAL,
    total_flight_count = 0,
    daily_flight_count = 0
}
local telemetry_initialized = false

-- Log and flight counters
local model_index_file = SYSTEM_LOG_ROOT .. "/model_index.txt"
local file_name = ""
local file_path = ""
local file_obj
local log_info = ""
local log_data = {}
local fly_number = 0
local second = { 0, 0, 0 }
local total_second = 0
local hours = 0
local minutes = { 0, 0 }
local seconds = { 0, 0 }
local power_max = { 0, 0 }
local write_en_flag = false
local arm_flag = false
local last_arm_status = 0
local session_flight_count = 0
local current_flight_max_current = 0
local led_cache = { mode = "", phase = -1 }
local low_battery_alert_active = false
local low_battery_alert_time = 0
local last_arm_audio_state = nil
local last_gov_audio_state = nil
local last_profile_audio_state = nil
local last_config_reload_time = -1
local CONFIG_RELOAD_INTERVAL = 60
local REFRESH_INTERVAL_TICKS = 10 -- getTime() uses 10 ms ticks: 10 FPS
local disable_flags_cache = { value = nil, text = "OK" }
local status_lines_cache = { text = nil, lines = {} }
local gauge_geometry_cache = nil

-- Deferred main-log write state
local write_state = 0
local write_snapshot = nil

-- Arming disable text map
local ARM_DISABLE_FLAG_NAMES = {
    [0] = "NO GYRO",
    [1] = "FAIL SAFE",
    [2] = "RX FAIL SAFE",
    [3] = "BAD RX RECOVERY",
    [4] = "BOX FAIL SAFE",
    [5] = "GOVERNOR",
    [7] = "THROTTLE",
    [8] = "ANGLE",
    [9] = "BOOT GRACE",
    [10] = "NO PREARM",
    [11] = "LOAD",
    [12] = "CALIBRATING",
    [13] = "CLI",
    [14] = "CMS MENU",
    [15] = "BST",
    [16] = "MSP",
    [17] = "PARALYZE",
    [18] = "GPS",
    [19] = "RESC",
    [20] = "RPM FILTER",
    [21] = "REBOOT REQD",
    [22] = "DSHOT BITBANG",
    [23] = "ACC CAL",
    [24] = "MOTOR PROTO",
    [25] = "ARM SWITCH"
}

local options = {
    { "SquareColor", COLOR, WHITE },
    { "ValueColor", COLOR, GREEN },
    { "DispLED", BOOL, 0 },
    { "UseGovernor", BOOL, 1 },
    { "HoldSwitch", SWITCH, 0 },
    { "BatAlertPct", VALUE, DEFAULT_BATTERY_ALERT_PCT, 0, 100 }
}
local radioH = 0
local function build_default_log_info()
    return string.format("%d", getDateTime().year) .. '/' ..
        string.format("%02d", getDateTime().mon) .. '/' ..
        string.format("%02d", getDateTime().day) .. '|' ..
        "00:00:00" .. '|' ..
        "00\n"
end

local function sanitize_model_name(model_name)
    if not model_name or model_name == "" then
        return ""
    end

    return string.gsub(model_name, "[<>:\"/\\|?*]", "")
end

local function build_date_stamp(date_time)
    return string.format("%d%02d%02d", date_time.year, date_time.mon, date_time.day)
end

local function build_daily_log_file_name(safe_model_name, date_time)
    return "[" .. safe_model_name .. "]" .. build_date_stamp(date_time) .. ".log"
end

local update_cached_flight_counts

local function set_led_strip_off()
    for i = 0, LED_STRIP_LENGTH - 1 do
        setRGBLedColor(i, 0, 0, 0)
    end
    applyRGBLedColors()
end

local function set_led_strip_solid(red, green, blue)
    for i = 0, LED_STRIP_LENGTH - 1 do
        setRGBLedColor(i, red, green, blue)
    end
    applyRGBLedColors()
end

local function set_led_strip_circulating_red(phase)
    local half_length = math.max(1, math.floor(LED_STRIP_LENGTH / 2))
    local travel_length = math.max(1, half_length - 1)
    local cycle_length = math.max(1, (travel_length * 2))
    local scanner_position = phase % cycle_length

    if scanner_position >= travel_length then
        scanner_position = cycle_length - scanner_position
    end

    for i = 0, LED_STRIP_LENGTH - 1 do
        setRGBLedColor(i, 8, 0, 0)
    end

    for strip_index = 0, 1 do
        local strip_offset = strip_index * half_length

        for trail_index = 1, #LED_TRAIL_COLORS do
            local led_index = strip_offset + scanner_position + trail_index - 1
            if led_index < strip_offset + half_length and led_index < LED_STRIP_LENGTH then
                local color = LED_TRAIL_COLORS[trail_index]
                setRGBLedColor(led_index, color[1], color[2], color[3])
            end
        end
    end

    applyRGBLedColors()
end

function update_led_strip(widget, is_armed, has_disable_flags)
    if not LED_STRIP_LENGTH or LED_STRIP_LENGTH <= 0 then
        return
    end

    if widget.options.DispLED ~= 1 then
        if led_cache.mode ~= "OFF" then
            led_cache.mode = "OFF"
            led_cache.phase = -1
            set_led_strip_off()
        end
        return
    end

    if has_disable_flags then
        local phase = math.floor(getTime() / 2)
        if led_cache.mode ~= "DISABLE" or led_cache.phase ~= phase then
            led_cache.mode = "DISABLE"
            led_cache.phase = phase
            set_led_strip_circulating_red(phase)
        end
    elseif is_armed then
        if led_cache.mode ~= "ARMED" then
            led_cache.mode = "ARMED"
            led_cache.phase = -1
            set_led_strip_solid(0, 80, 255)
        end
    else
        if led_cache.mode ~= "DISARMED" then
            led_cache.mode = "DISARMED"
            led_cache.phase = -1
            set_led_strip_solid(255, 0, 0)
        end
    end
end

local function load_model_index()
    local models = {}
    local file_info = fstat(model_index_file)
    if file_info and file_info.size > 0 then
        local file_obj = io.open(model_index_file, "r")
        if file_obj then
            local content = io.read(file_obj, file_info.size)
            io.close(file_obj)
            local start_pos = 1
            while start_pos <= #content do
                local end_pos = string.find(content, "\n", start_pos)
                if not end_pos then
                    end_pos = #content + 1
                end
                local line = string.sub(content, start_pos, end_pos - 1)
                local model_name = string.gsub(line, "\r", "")
                if model_name ~= "" then
                    table.insert(models, model_name)
                end
                start_pos = end_pos + 1
            end
        end
    end
    return models
end
local function update_model_index(model_name)
    if not model_name or model_name == "" or model_name == ">Rotorflight" then
        return
    end
    local models = load_model_index()
    local exists = false
    for i = 1, #models do
        if models[i] == model_name then
            exists = true
            break
        end
    end
    if not exists then
        table.insert(models, model_name)
        local file_obj = io.open(model_index_file, "w")
        if file_obj then
            for i = 1, #models do
                io.write(file_obj, models[i] .. "\n")
            end
            io.close(file_obj)
        end
    end
end

local function create(zone, options)
    local config = widget_config.load(true)
    last_config_reload_time = getRtcTime() or 0
    if not options.BatAlertPct or options.BatAlertPct == "" then
        options.BatAlertPct = config.battery_alert_pct
    end

    local widget = {
        zone = zone,
        options = options,
        last_refresh_tick = -REFRESH_INTERVAL_TICKS
    }
    for i = 1, TELE_ITEMS do
        value_min_max[i] = { 0, 0, 0 }
        field_id[i] = { 0, false }
    end
    runtime_cache.model_name = ""
    runtime_cache.safe_model_name = ""
    runtime_cache.log_date_stamp = ""
    runtime_cache.pic_path = ""
    runtime_cache.pilot_name = config.pilot_name
    runtime_cache.battery_alert_pct = config.battery_alert_pct
    runtime_cache.battery_alert_interval = config.battery_alert_interval
    runtime_cache.total_flight_count = 0
    runtime_cache.daily_flight_count = 0
    telemetry_initialized = false
    for k, v in pairs(crsf_field) do
        local field_info = getFieldInfo(v)
        if field_info ~= nil then
            field_id[k][1] = field_info.id
            field_id[k][2] = true
        else
            field_id[k][1] = 0
            field_id[k][2] = false
        end
    end
    for i = 1, #second do
        second[i] = 0
    end
    total_second = 0
    write_en_flag = false
    arm_flag = false
    current_flight_max_current = 0
    low_battery_alert_active = false
    low_battery_alert_time = 0
    last_arm_audio_state = nil
    last_gov_audio_state = nil
    telemetry_initialized = false
    local date_time = getDateTime()
    file_name = "[" .. WIDGET_DIR .. "]" .. build_date_stamp(date_time) .. ".log"
    file_path = LOG_ROOT .. "/" .. file_name
    local file_info = fstat(file_path)
    local read_count = 1
    if file_info ~= nil then
        if file_info.size > 0 then
            file_obj = io.open(file_path, "r")
            if file_obj then
                log_info = io.read(file_obj, LOG_INFO_LEN + 1)
                while true do
                    log_data[read_count] = io.read(file_obj, LOG_DATA_LEN + 1)
                    if #log_data[read_count] == 0 then
                        break
                    else
                        read_count = read_count + 1
                    end
                end
                io.close(file_obj)
                hours = string.sub(log_info, 12, 13)
                minutes[2] = string.sub(log_info, 15, 16)
                seconds[2] = string.sub(log_info, 18, 19)
                total_second = tonumber(string.sub(log_info, 12, 13)) * 3600
                total_second = total_second + tonumber(string.sub(log_info, 15, 16)) * 60
                total_second = total_second + tonumber(string.sub(log_info, 18, 19))
            else
                log_info = build_default_log_info()
                log_data = {}
            end
        else
            log_info = build_default_log_info()
        end
    else
        file_obj = io.open(file_path, "w")
        log_info = build_default_log_info()
        if file_obj then
            io.write(file_obj, log_info)
            io.close(file_obj)
        end
    end
    local str_temp = string.sub(log_info, 21, 23)
    if tonumber(str_temp) ~= nil then
        fly_number = tonumber(str_temp)
    end
    if fly_number == 0 then
        fly_number = 1
        log_data[1] = "01|12:34:56|05:30|1850|025|2400|125.5|03500|25.2|22.8|+055|+025|+040|+020|-032|-072|-028|-065|100|095|080|12.6|11.8\n"
    end
    default_pic_obj = Bitmap.open(IMAGE_ROOT .. "/default.png")
    hold1_pic_obj = Bitmap.open(IMAGE_ROOT .. "/hold1.png")
    hold2_pic_obj = Bitmap.open(IMAGE_ROOT .. "/hold2.png")
    local current_model = model.getInfo().name
    if current_model and current_model ~= "" then
        update_model_index(current_model)
        update_cached_flight_counts(current_model, date_time)
    end
    return widget
end

local function reload_runtime_config(widget)
    local now = getRtcTime() or 0
    if last_config_reload_time >= 0 and now >= last_config_reload_time
        and (now - last_config_reload_time) < CONFIG_RELOAD_INTERVAL then
        return
    end

    last_config_reload_time = now

    local config = widget_config.load(false)
    runtime_cache.pilot_name = config.pilot_name or DEFAULT_PILOT_NAME
    runtime_cache.battery_alert_pct = config.battery_alert_pct or DEFAULT_BATTERY_ALERT_PCT
    runtime_cache.battery_alert_interval = config.battery_alert_interval or DEFAULT_BATTERY_ALERT_INTERVAL
end

local function update(widget, options)
    if not options.BatAlertPct or options.BatAlertPct == "" then
        options.BatAlertPct = runtime_cache.battery_alert_pct or DEFAULT_BATTERY_ALERT_PCT
    end

    widget.options = options
end
local function background(widget)
end
local function get_battery_alert_threshold(widget)
    local threshold = tonumber(widget.options.BatAlertPct) or 0
    if threshold < 0 then
        return 0
    end
    if threshold > 100 then
        return 100
    end
    return math.floor(threshold)
end

local function play_widget_audio(file_name)
    playFile("/WIDGETS/" .. WIDGET_DIR .. "/audio/" .. file_name)
end

local function get_governor_audio_file(gov_text)
    if gov_text == "OFF" then
        return "gov/off.wav"
    end
    if gov_text == "SPOOLUP" then
        return "gov/spoolup.wav"
    end
    if gov_text == "ACTIVE" then
        return "gov/active.wav"
    end
    return nil
end

local function get_profile_number_audio_file(profile_value)
    return PROFILE_AUDIO_FILES[profile_value]
end

local function play_triple_haptic()
    playHaptic(15, 0)
    playHaptic(15, 0)
    playHaptic(15, 0)
end

function update_profile_audio(profile_value, has_profile_sensor)
    if not has_profile_sensor then
        last_profile_audio_state = nil
        return
    end

    local profile_audio_state = math.floor(tonumber(profile_value) or 0)
    if last_profile_audio_state == nil then
        last_profile_audio_state = profile_audio_state
        return
    end

    if profile_audio_state ~= last_profile_audio_state then
        if profile_audio_state > 0 then
            play_widget_audio("profile.wav")
            local profile_number_audio_file = get_profile_number_audio_file(profile_audio_state)
            if profile_number_audio_file then
                play_widget_audio(profile_number_audio_file)
            end
        end
        last_profile_audio_state = profile_audio_state
    end
end

function update_arm_audio(is_armed, has_arm_sensor)
    if not has_arm_sensor then
        last_arm_audio_state = nil
        return
    end

    local arm_audio_state = is_armed and "ARMED" or "DISARMED"
    if last_arm_audio_state == nil then
        last_arm_audio_state = arm_audio_state
        return
    end

    if arm_audio_state ~= last_arm_audio_state then
        if arm_audio_state == "ARMED" then
            play_widget_audio("armed.wav")
        else
            play_widget_audio("disarmed.wav")
        end
        last_arm_audio_state = arm_audio_state
    end
end

function update_governor_audio(gov_text, has_governor_state)
    if not has_governor_state or not gov_text then
        last_gov_audio_state = nil
        return
    end

    local gov_audio_file = get_governor_audio_file(gov_text)

    if last_gov_audio_state == nil then
        last_gov_audio_state = gov_text
        return
    end

    if gov_text ~= last_gov_audio_state then
        if gov_audio_file then
            play_widget_audio(gov_audio_file)
        end
        last_gov_audio_state = gov_text
    end
end

local function is_governor_enabled(widget)
    return not widget or widget.options.UseGovernor ~= 0
end

function update_low_battery_alert(widget, battery_percent, is_armed, has_battery_percent)
    local threshold = get_battery_alert_threshold(widget)
    local should_alert = has_battery_percent and is_armed and threshold > 0 and battery_percent <= threshold
    local alert_interval = runtime_cache.battery_alert_interval or DEFAULT_BATTERY_ALERT_INTERVAL

    if should_alert then
        local now = getRtcTime() or 0
        if not low_battery_alert_active or (now - low_battery_alert_time) >= alert_interval then
            play_widget_audio("lowfuel.wav")
            play_triple_haptic()
            low_battery_alert_active = true
            low_battery_alert_time = now
        end
        return
    end

    low_battery_alert_active = false
    low_battery_alert_time = 0
end

local function get_total_flight_count(model_name)
    if not model_name or model_name == "" then
        return 0
    end
    local safe_model_name = sanitize_model_name(model_name)
    local total_file_path = SYSTEM_LOG_ROOT .. "/totalall_[" .. safe_model_name .. "].txt"
    local file_info = fstat(total_file_path)
    if file_info and file_info.size > 0 then
        local file = io.open(total_file_path, "r")
        if file then
            local content = io.read(file, 100)
            io.close(file)
            local count = tonumber(content)
            if count then
                return count
            end
        end
    end
    return 0
end

update_cached_flight_counts = function(model_name, date_time)
    if not model_name or model_name == "" then
        runtime_cache.total_flight_count = 0
        runtime_cache.daily_flight_count = 0
        return
    end

    local safe_model_name = sanitize_model_name(model_name)
    runtime_cache.total_flight_count = get_total_flight_count(model_name)
    runtime_cache.daily_flight_count = 0

    if safe_model_name == "" then
        return
    end

    local target_file_path = LOG_ROOT .. "/" .. build_daily_log_file_name(safe_model_name, date_time)
    local file_info = fstat(target_file_path)
    if file_info and file_info.size > 0 then
        local temp_file_obj = io.open(target_file_path, "r")
        if temp_file_obj then
            local temp_log_info = io.read(temp_file_obj, LOG_INFO_LEN + 1)
            if temp_log_info and string.len(temp_log_info) >= 23 then
                runtime_cache.daily_flight_count = tonumber(string.sub(temp_log_info, 21, 23)) or 0
            end
            io.close(temp_file_obj)
        end
    end
end

local function increment_total_flight_count(model_name)
    if not model_name or model_name == "" then
        return
    end
    local safe_model_name = sanitize_model_name(model_name)
    local total_file_path = SYSTEM_LOG_ROOT .. "/totalall_[" .. safe_model_name .. "].txt"
    local current_count = get_total_flight_count(model_name)
    local new_count = current_count + 1
    local file = io.open(total_file_path, "w")
    if file then
        io.write(file, tostring(new_count))
        io.close(file)
    end
end
local function draw_rounded_rectangle(xs, ys, w, h, r, color)
    lcd.drawArc(xs + r, ys + r, r, 270, 360, color)
    lcd.drawArc(xs + r, ys + h - r, r, 180, 270, color)
    lcd.drawArc(xs + w - r, ys + r, r, 0, 90, color)
    lcd.drawArc(xs + w - r, ys + h - r, r, 90, 180, color)
    lcd.drawLine(xs + r, ys, xs + w - r, ys, SOLID, color)
    lcd.drawLine(xs + r, ys + h, xs + w - r, ys + h, SOLID, color)
    lcd.drawLine(xs, ys + r, xs, ys + h - r, SOLID, color)
    lcd.drawLine(xs + w, ys + r, xs + w, ys + h - r, SOLID, color)
end
function rqly_signal_bars_ladder(xs, ys, rqly_percent, default_color, size)
    local bar_count = 6
    local bar_width = math.floor(6 * size)
    local bar_spacing = math.floor(2 * size)
    local base_height = math.floor(4 * size)
    local height_increment = math.floor(4 * size)
    rqly_percent = math.max(0, math.min(100, rqly_percent))
    local active_bars = math.floor((rqly_percent + 8) / 16.67)
    for i = 1, bar_count do
        local bar_x = xs + (i - 1) * (bar_width + bar_spacing)
        local bar_height = base_height + (i - 1) * height_increment
        local bar_y = ys - bar_height
        local bar_color = default_color
        if rqly_percent > 0 and i <= active_bars then
            if i == 1 then
                bar_color = RED
            elseif i == 2 then
                bar_color = ORANGE
            elseif i == 3 then
                bar_color = YELLOW
            elseif i == 4 then
                bar_color = lcd.RGB(173, 255, 47)
            elseif i == 5 then
                bar_color = lcd.RGB(0, 255, 0)
            else
                bar_color = GREEN
            end
        end
        lcd.drawFilledRectangle(bar_x, bar_y, bar_width, bar_height, bar_color)
    end
end
function draw_gauge_meter(xs, ys, value, max_value, size, color, bg_color)
    local radius = size
    local start_angle = 180
    local end_angle = 270
    local range_angle = end_angle - start_angle
    value = math.max(0, math.min(max_value, value))
    if not gauge_geometry_cache or gauge_geometry_cache.x ~= xs
        or gauge_geometry_cache.y ~= ys or gauge_geometry_cache.radius ~= radius then
        local geometry = { x = xs, y = ys, radius = radius, scale = {}, ticks = {}, arcs = {} }
        for i = 1, #GAUGE_SCALE_STEPS do
            local step = GAUGE_SCALE_STEPS[i]
            local rad = math.rad(190 + (step / 100) * 70)
            geometry.scale[i] = {
                xs + math.cos(rad) * (radius * 0.80), ys + math.sin(rad) * (radius * 0.80),
                xs + math.cos(rad) * (radius * 0.92), ys + math.sin(rad) * (radius * 0.92),
                xs + math.cos(rad) * (radius * 1.25), ys + math.sin(rad) * (radius * 1.25),
                tostring(step)
            }
        end
        for tick = 0, 100, 4 do
            local rad = math.rad(start_angle + (tick / 100) * range_angle)
            geometry.ticks[#geometry.ticks + 1] = {
                xs + math.cos(rad) * (radius * 0.86), ys + math.sin(rad) * (radius * 0.86),
                xs + math.cos(rad) * (radius * 0.92), ys + math.sin(rad) * (radius * 0.92)
            }
        end
        -- Fewer, wider angular segments retain the six-pixel arc thickness
        -- while cutting arc calls from 270 to 144 per refresh.
        for seg = 0, 23 do
            local percent = seg / 24
            geometry.arcs[#geometry.arcs + 1] = {
                270 + 90 * percent, 270 + 90 * ((seg + 1) / 24),
                math.floor(percent * 255), math.floor(255 - percent * 255)
            }
        end
        gauge_geometry_cache = geometry
    end

    for i = 1, #gauge_geometry_cache.scale do
        local mark = gauge_geometry_cache.scale[i]
        lcd.drawLine(mark[1], mark[2], mark[3], mark[4], SOLID, color)
        lcd.drawText(mark[5], mark[6], mark[7], SMLSIZE + color)
    end
    for i = 1, #gauge_geometry_cache.ticks do
        local tick = gauge_geometry_cache.ticks[i]
        lcd.drawLine(tick[1], tick[2], tick[3], tick[4], SOLID, bg_color)
    end
    local value_percent = value / max_value * 100
    for i = 1, #gauge_geometry_cache.arcs do
        local arc = gauge_geometry_cache.arcs[i]
        local seg_color = lcd.RGB(arc[3], arc[4], 0)
        for w = 0, 5 do
            lcd.drawArc(xs, ys, radius * 0.92 + w, arc[1], arc[2], seg_color)
        end
    end
    local value_angle = start_angle + (value_percent / 100) * range_angle
    local pointer_angle = value_angle
    local pointer_rad = math.rad(pointer_angle)
    local offset_angle = 232
    local offset_rad = math.rad(offset_angle)
    local offset_distance = radius * 0.08
    local center_x = xs + math.cos(offset_rad) * offset_distance
    local center_y = ys + math.sin(offset_rad) * offset_distance
    local pointer_length = radius * 0.60
    local pointer_x = center_x + math.cos(pointer_rad) * pointer_length
    local pointer_y = center_y + math.sin(pointer_rad) * pointer_length
    lcd.drawLine(center_x, center_y, pointer_x, pointer_y, SOLID, color)
    lcd.drawLine(center_x + 1, center_y, pointer_x + 1, pointer_y, SOLID, color)
    lcd.drawLine(center_x, center_y + 1, pointer_x, pointer_y + 1, SOLID, color)
    lcd.drawLine(center_x - 1, center_y, pointer_x - 1, pointer_y, SOLID, color)
    lcd.drawLine(center_x, center_y - 1, pointer_x, pointer_y - 1, SOLID, color)
    lcd.drawFilledCircle(center_x, center_y, math.max(3, radius * 0.08), color)
end
local function draw_digit_segment(x, y, digit, seg_width, seg_height, seg_thickness, color, bg_color)
    local segs = DIGIT_SEGMENTS[digit] or DIGIT_SEGMENTS[0]
    if segs[1] == 1 then
        lcd.drawFilledRectangle(x + seg_thickness, y, seg_width, seg_thickness, color)
    end
    if segs[2] == 1 then
        lcd.drawFilledRectangle(x + seg_width + seg_thickness, y + seg_thickness, seg_thickness, seg_height, color)
    end
    if segs[3] == 1 then
        lcd.drawFilledRectangle(x + seg_width + seg_thickness, y + seg_height + seg_thickness * 2, seg_thickness, seg_height, color)
    end
    if segs[4] == 1 then
        lcd.drawFilledRectangle(x + seg_thickness, y + seg_height * 2 + seg_thickness * 2, seg_width, seg_thickness, color)
    end
    if segs[5] == 1 then
        lcd.drawFilledRectangle(x, y + seg_height + seg_thickness * 2, seg_thickness, seg_height, color)
    end
    if segs[6] == 1 then
        lcd.drawFilledRectangle(x, y + seg_thickness, seg_thickness, seg_height, color)
    end
    if segs[7] == 1 then
        lcd.drawFilledRectangle(x + seg_thickness, y + seg_height + seg_thickness, seg_width, seg_thickness, color)
    end
end
function draw_time_display(x, y, hours, minutes, digit_size, color)
    local seg_width = digit_size * 0.6
    local seg_height = digit_size * 0.5
    local seg_thickness = digit_size * 0.15
    local digit_spacing = digit_size * 1.2
    local gray_color = lcd.RGB(80, 80, 80)
    local colon_size = seg_thickness * 1.5
    hours = math.max(0, math.min(23, hours))
    minutes = math.max(0, math.min(59, minutes))
    local current_x = x
    local hour_tens = math.floor(hours / 10)
    draw_digit_segment(current_x, y, hour_tens, seg_width, seg_height, seg_thickness, color, gray_color)
    current_x = current_x + digit_spacing
    local hour_ones = hours % 10
    draw_digit_segment(current_x, y, hour_ones, seg_width, seg_height, seg_thickness, color, gray_color)
    current_x = current_x + digit_spacing
    local colon_y1 = y + seg_height * 0.6
    local colon_y2 = y + seg_height * 1.4 + seg_thickness
    lcd.drawFilledRectangle(current_x - digit_spacing * 0.05, colon_y1, colon_size, colon_size, color)
    lcd.drawFilledRectangle(current_x - digit_spacing * 0.05, colon_y2, colon_size, colon_size, color)
    current_x = current_x + digit_spacing * 0.3
    local min_tens = math.floor(minutes / 10)
    draw_digit_segment(current_x, y, min_tens, seg_width, seg_height, seg_thickness, color, gray_color)
    current_x = current_x + digit_spacing
    local min_ones = minutes % 10
    draw_digit_segment(current_x, y, min_ones, seg_width, seg_height, seg_thickness, color, gray_color)
end

local function arming_disable_flags_to_string(flags)
    if flags == nil then
        return "OK"
    end

    flags = math.floor(flags)
    if disable_flags_cache.value == flags then
        return disable_flags_cache.text
    end

    local names = {}
    for i = 0, 25 do
        local mask = 2 ^ i
        if math.floor(flags / mask) % 2 == 1 then
            local name = ARM_DISABLE_FLAG_NAMES[i]
            if name and name ~= "" then
                table.insert(names, name)
            end
        end
    end

    if #names == 0 then
        disable_flags_cache.value = flags
        disable_flags_cache.text = "OK"
        return disable_flags_cache.text
    end

    disable_flags_cache.value = flags
    disable_flags_cache.text = table.concat(names, ", ")
    return disable_flags_cache.text
end

local function wrap_disable_flags_text(text, max_chars_per_line, max_lines)
    local lines = {}
    local current_line = ""

    if not text or text == "" then
        return lines
    end

    for part in string.gmatch(text, "[^,]+") do
        local word = string.gsub(part, "^%s*(.-)%s*$", "%1")
        if word ~= "" then
            if current_line == "" then
                current_line = word
            elseif (#current_line + #word + 2) <= max_chars_per_line then
                current_line = current_line .. ", " .. word
            else
                table.insert(lines, current_line)
                current_line = word
                if #lines >= max_lines then
                    break
                end
            end
        end
    end

    if #lines < max_lines and current_line ~= "" then
        table.insert(lines, current_line)
    end

    if #lines == max_lines and text ~= table.concat(lines, ", ") then
        local last = lines[max_lines]
        if #last > max_chars_per_line - 3 then
            last = string.sub(last, 1, max_chars_per_line - 3)
        end
        lines[max_lines] = last .. "..."
    end

    return lines
end

function draw_status_block(x, y, text, color)
    local lines = status_lines_cache.lines
    if status_lines_cache.text ~= text then
        lines = wrap_disable_flags_text(text, 16, 2)
        status_lines_cache.text = text
        status_lines_cache.lines = lines
    end
    if #lines == 0 then
        lcd.drawText(x, y, "...", SMLSIZE + color)
        return
    end

    for i = 1, #lines do
        lcd.drawText(x, y + ((i - 1) * 16), lines[i], SMLSIZE + color)
    end
end

function get_governor_state_text(gov_value, has_gov_sensor, throttle_value)
    if has_gov_sensor and gov_value ~= nil then
        return GOVERNOR_STATE_NAMES[gov_value] or "UNKNOWN"
    end

    if throttle_value == nil then
        return "UNKNOWN"
    end

    throttle_value = math.floor(tonumber(throttle_value) or 0)
    if throttle_value <= 0 then
        return "OFF"
    end
    if throttle_value <= 50 then
        return "SPOOLUP"
    end

    return "ACTIVE"
end
function draw_ring_progress(xs, ys, value, max_value, size)
    local radius = size
    local ring_width = 8
    local segments = 20
    local gap = 3
    local angle_coverage = 270
    local segments_to_draw = 15
    local start_angle = -135
    local gray_color = lcd.RGB(80, 80, 80)
    value = math.max(0, math.min(max_value, value))
    local progress_percent = value / max_value
    local active_segments = math.floor(segments_to_draw * progress_percent)
    for i = 0, segments_to_draw - 1 do
        local angle_start = (360 / segments) * i + start_angle + gap / 2
        local angle_end = (360 / segments) * (i + 1) + start_angle - gap / 2
        local segment_color = gray_color
        if i < active_segments then
            local seg_percent = (i / (segments_to_draw - 1)) * 100
            local r = math.floor(seg_percent * 2.55)
            local g = math.floor(255 - (seg_percent * 2.55))
            local b = 0
            segment_color = lcd.RGB(r, g, b)
        end
        lcd.drawAnnulus(xs, ys, radius - ring_width, radius, angle_start, angle_end, segment_color)
    end
end
function draw_power_gauge(center_x, center_y, radius, power_value, max_power, gauge_color, needle_color)
    local display_max = max_power or 5000
    power_value = math.max(0, math.min(display_max, power_value))
    local start_angle = 225
    local end_angle = 135
    local total_sweep = 270
    lcd.drawArc(center_x, center_y, radius, start_angle, 360, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, start_angle, 360, gauge_color)
    lcd.drawArc(center_x, center_y, radius, 0, end_angle, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, 0, end_angle, gauge_color)
    local num_ticks = 11
    for i = 0, num_ticks - 1 do
        local angle_deg = start_angle - (i * 27)
        local angle_rad = math.rad(angle_deg)
        local tick_start_r = radius - 5
        local tick_end_r = radius - 12
        local x1 = center_x + tick_start_r * math.cos(angle_rad)
        local y1 = center_y - tick_start_r * math.sin(angle_rad)
        local x2 = center_x + tick_end_r * math.cos(angle_rad)
        local y2 = center_y - tick_end_r * math.sin(angle_rad)
        lcd.drawLine(x1, y1, x2, y2, SOLID, gauge_color)
        if i % 2 == 0 then
            local value = (display_max / 10) * i
            local label = ""
            if value >= 1000 then
                label = string.format("%.0fk", value / 1000)
            else
                label = string.format("%.0f", value)
            end
            local text_r = radius - 22
            local text_x = center_x + text_r * math.cos(angle_rad)
            local text_y = center_y - text_r * math.sin(angle_rad)
            lcd.drawText(text_x, text_y, label, SMLSIZE + gauge_color + CENTER + VCENTER)
        end
    end
    local percentage = power_value / display_max
    local needle_angle_deg = start_angle - (percentage * total_sweep)
    local needle_angle_rad = math.rad(needle_angle_deg)
    local needle_length = radius - 15
    local needle_x = center_x + needle_length * math.cos(needle_angle_rad)
    local needle_y = center_y - needle_length * math.sin(needle_angle_rad)
    lcd.drawLine(center_x, center_y, needle_x, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x + 1, center_y, needle_x + 1, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x, center_y + 1, needle_x, needle_y + 1, SOLID, needle_color)
    lcd.drawFilledRectangle(center_x - 2, center_y - 2, 5, 5, needle_color)
    local power_str = ""
        power_str = string.format("%.0fA", power_value)
    lcd.drawText(center_x, center_y + 55, power_str,  needle_color + CENTER + VCENTER)
end
function draw_digital_display(x, y, value, num_digits, decimal_places, digit_size, color)
    local seg_width = digit_size * 0.6
    local seg_height = digit_size * 0.5
    local seg_thickness = digit_size * 0.15
    local digit_spacing = digit_size * 1.2
    local gray_color = lcd.RGB(80, 80, 80)
    local dot_size = seg_thickness
    local multiplier = math.pow(10, decimal_places)
    local int_part = math.floor(value)
    local dec_part = math.floor((value - int_part) * multiplier + 0.5)
    if dec_part >= multiplier then
        int_part = int_part + 1
        dec_part = 0
    end
    local max_int_value = math.pow(10, num_digits) - 1
    int_part = math.min(max_int_value, int_part)
    local int_value_digits = 0
    if int_part == 0 then
        int_value_digits = 1
    else
        int_value_digits = math.floor(math.log(int_part) / math.log(10)) + 1
    end
    local current_x = x
    for i = 0, num_digits - 1 do
        local divisor = math.pow(10, num_digits - 1 - i)
        local digit = math.floor(int_part / divisor) % 10
        local digit_color = gray_color
        local is_leading_zero = true
        if i >= (num_digits - int_value_digits) then
            digit_color = color
            is_leading_zero = false
        end
        draw_digit_segment(current_x, y, digit, seg_width, seg_height, seg_thickness, digit_color, gray_color)
        current_x = current_x + digit_spacing
    end
    if decimal_places > 0 then
        local dot_y = y + seg_height * 2 + seg_thickness * 2
        lcd.drawFilledRectangle(current_x - digit_spacing * 0.15, dot_y, dot_size, dot_size, color)
    end
    for i = 0, decimal_places - 1 do
        local divisor = math.pow(10, decimal_places - 1 - i)
        local digit = math.floor(dec_part / divisor) % 10
        draw_digit_segment(current_x, y, digit, seg_width, seg_height, seg_thickness, color, gray_color)
        current_x = current_x + digit_spacing
    end
end
local function refresh(widget, event, touchState)
    -- On touch radios EdgeTX may promote a tapped widget to full-screen mode.
    -- Leave that mode immediately so the top bar and SYS/MDL keys stay active.
    if touchState and lcd.exitFullScreen then
        lcd.exitFullScreen()
    end

    local refresh_tick = getTime()
    local elapsed_ticks = refresh_tick - (widget.last_refresh_tick or -REFRESH_INTERVAL_TICKS)
    if not touchState and elapsed_ticks >= 0 and elapsed_ticks < REFRESH_INTERVAL_TICKS then
        return
    end
    widget.last_refresh_tick = refresh_tick

    reload_runtime_config(widget)
    local date_time = getDateTime()
    local screen_width =  LCD_W or widget.zone.w
    local screen_height =  LCD_H or widget.zone.h
    lcd.setColor(CUSTOM_COLOR, BLACK)
    local bg_color = lcd.getColor(CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, widget.options.SquareColor)
    local square_color = lcd.getColor(CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, widget.options.ValueColor)
    local value_color = lcd.getColor(CUSTOM_COLOR)
    lcd.drawFilledRectangle(0, 0, screen_width, screen_height, bg_color)
    if not bg_pic_obj then
        bg_pic_obj = Bitmap.open(IMAGE_ROOT .. "/background.png")
    end
    if bg_pic_obj then
        lcd.drawBitmap(bg_pic_obj, 0, 0)
    end
    local model_name = model.getInfo().name or ""
    lcd.drawText(720, 414, model_name, RIGHT + MIDSIZE + value_color)
    if tg_pic_obj then
           lcd.drawBitmap(tg_pic_obj, 530, 190)        
    else
        if default_pic_obj then
            lcd.drawBitmap(default_pic_obj, 530, 190)
        end
    end
    local tx_voltage = getValue("tx-voltage") or getValue("TxBt") or 0
    local tx_battery_str = string.format("%.1fV", tx_voltage)
    local tx_color = value_color
    if tx_voltage < 6.5 then
        tx_color = RED
    elseif tx_voltage >= 6.5 and tx_voltage <= 7.0 then
        tx_color = YELLOW
    end
    lcd.drawText(682, 14, "Tx ", BOLD + square_color)
    lcd.drawText(714, 14, tx_battery_str, BOLD + tx_color)
    local rqly_percent = (field_id[10][2] and value_min_max[10][1]) or 0
    rqly_signal_bars_ladder(316, 60, rqly_percent, lcd.RGB(80, 80, 80), 1.0)
    if rqly_percent > 0 then
        lcd.drawText(452, 50, string.format("%ddB", rqly_percent), RIGHT + VCENTER + value_color)
    else
        lcd.drawText(452, 50, "---", RIGHT + VCENTER + MIDSIZE + RED)
    end
    local has_telemetry = false
    if field_id[10][2] then
        if rqly_percent > 0 then
            has_telemetry = true
        end
    end
    if has_telemetry and not telemetry_initialized then
        telemetry_initialized = true
    end
    local current_model_name = model_name
    local current_date_stamp = build_date_stamp(date_time)
    local should_load_log = false
    if rqly_percent > 0 and not telemetry_initialized then
        telemetry_initialized = true
        should_load_log = true
    end
    if current_model_name ~= runtime_cache.model_name and current_model_name ~= "" then
        runtime_cache.model_name = current_model_name
        runtime_cache.safe_model_name = sanitize_model_name(current_model_name)
        runtime_cache.pic_path = MODEL_IMAGE_ROOT .. "/" .. string.sub(runtime_cache.model_name, 2) .. ".png"
        runtime_cache.log_date_stamp = current_date_stamp
        should_load_log = true
    elseif current_model_name ~= "" and runtime_cache.log_date_stamp ~= current_date_stamp then
        runtime_cache.log_date_stamp = current_date_stamp
        should_load_log = true
    end
    if should_load_log and current_model_name and current_model_name ~= "" then
        local safe_model_name = runtime_cache.safe_model_name ~= "" and runtime_cache.safe_model_name or sanitize_model_name(current_model_name)
        local new_file_name = build_daily_log_file_name(safe_model_name, date_time)
        local new_file_path = LOG_ROOT .. "/" .. new_file_name
        if fstat(runtime_cache.pic_path) then
            tg_pic_obj = Bitmap.open(runtime_cache.pic_path)
        else
            tg_pic_obj = nil
        end
        file_name = new_file_name
        file_path = new_file_path
        log_data = {}
        local file_info = fstat(file_path)
        local read_count = 1
        if file_info ~= nil and file_info.size > 0 then
            local temp_file_obj = io.open(file_path, "r")
            if temp_file_obj then
                log_info = io.read(temp_file_obj, LOG_INFO_LEN + 1)
                while true do
                    log_data[read_count] = io.read(temp_file_obj, LOG_DATA_LEN + 1)
                    if #log_data[read_count] == 0 then
                        break
                    else
                        read_count = read_count + 1
                    end
                end
                io.close(temp_file_obj)
                if log_info and string.len(log_info) >= 23 then
                    hours = string.sub(log_info, 12, 13)
                    minutes[2] = string.sub(log_info, 15, 16)
                    seconds[2] = string.sub(log_info, 18, 19)
                    total_second = tonumber(string.sub(log_info, 12, 13)) * 3600
                    total_second = total_second + tonumber(string.sub(log_info, 15, 16)) * 60
                    total_second = total_second + tonumber(string.sub(log_info, 18, 19))
                    local str_temp = string.sub(log_info, 21, 23)
                    if tonumber(str_temp) ~= nil then
                        fly_number = tonumber(str_temp)
                    end
                    runtime_cache.daily_flight_count = fly_number
                end
            end
        else
            fly_number = 0
            runtime_cache.daily_flight_count = 0
            log_info = string.format("%d", date_time.year) .. '/' ..
                string.format("%02d", date_time.mon) .. '/' ..
                string.format("%02d", date_time.day) .. '|' ..
                "00:00:00" .. '|' ..
                "00\n"
        end
        update_cached_flight_counts(current_model_name, date_time)
        session_flight_count = 0
    end
    local hold_active = false
    if widget.options.HoldSwitch ~= 0 then
        local switch_value = getSwitchValue(widget.options.HoldSwitch)
        if switch_value and switch_value ~= 0 and switch_value ~= false then
            hold_active = true
        else
            hold_active = false
        end
    end
    if hold_active then
        if hold1_pic_obj then
            lcd.drawBitmap(hold1_pic_obj, 90, 25)
        end
    else
        if hold2_pic_obj then
            lcd.drawBitmap(hold2_pic_obj, 90, 25)
        end
    end
    for k = 1, TELE_ITEMS do
        if field_id[k][2] then
            local get_value = getValue(field_id[k][1])
            value_min_max[k][1] = get_value  
            if not hold_active then
                if get_value > value_min_max[k][2] then
                    value_min_max[k][2] = get_value
                elseif get_value < value_min_max[k][3] then
                    value_min_max[k][3] = get_value
                end
            end
        end
    end
    bank_info.current = (field_id[17][2] and value_min_max[17][1]) or 1
    local bank_color = square_color
    if bank_info.current == 1 then
        bank_color = lcd.RGB(0, 100, 255)
    elseif bank_info.current == 2 then
        bank_color = lcd.RGB(255, 165, 0)
    elseif bank_info.current == 3 then
        bank_color = lcd.RGB(255, 255, 0)
    end
    lcd.drawText(175, 44, tostring(bank_info.current), CENTER + VCENTER + BOLD + MIDSIZE + bank_color)
    local arm_status = (field_id[13][2] and value_min_max[13][1]) or 0
    local gov_enabled = is_governor_enabled(widget)
    local gov_status = (gov_enabled and field_id[14][2] and value_min_max[14][1]) or nil
    local throttle_value = (field_id[11][2] and value_min_max[11][1]) or nil
    local disable_flags = nil
    if field_id[18][2] then
        disable_flags = value_min_max[18][1]
    end
    if disable_flags == nil then
        disable_flags = getValue("ARMD")
    end
    if disable_flags == nil then
        disable_flags = getValue("Arming Disable")
    end
    local is_armed = false
    if field_id[13][2] then
        is_armed = (arm_status == 1 or arm_status == 3)
        if arm_status == 2 and last_arm_status ~= 2 and second[1] > 30 then
            session_flight_count = session_flight_count + 1
        end
        if is_armed and (last_arm_status == 0 or last_arm_status == 2) then
            current_flight_max_current = 0
        end
    end
    local arm_status_text = "DISARMED"
    local arm_status_color = RED
    local disable_flags_text = arming_disable_flags_to_string(disable_flags)
    if disable_flags_text ~= "OK" then
        arm_status_text = disable_flags_text
        arm_status_color = RED
    elseif is_armed then
        arm_status_text = "ARMED"
        arm_status_color = YELLOW
    elseif not field_id[13][2] then
        arm_status_text = "NO TELE"
        arm_status_color = RED + BLINK
    end
    update_led_strip(widget, is_armed, disable_flags_text ~= "OK")
    draw_status_block(480, 40, arm_status_text, arm_status_color)
    local gov_text = gov_enabled and get_governor_state_text(gov_status, field_id[14][2], throttle_value) or "DISABLED"
    update_profile_audio(bank_info.current, field_id[17][2])
    update_arm_audio(is_armed, field_id[13][2])
    update_governor_audio(gov_enabled and gov_text or nil, gov_enabled and (field_id[14][2] or field_id[11][2]))
    if field_id[13][2] then
        last_arm_status = arm_status
    end
    if is_armed then
        if arm_flag == false then
            arm_flag = true
            for s = 1, TELE_ITEMS do
                if field_id[s][2] then
                    value_min_max[s][2] = value_min_max[s][1]
                    value_min_max[s][3] = value_min_max[s][1]
                end
            end
            second[1] = 0
            power_max[1] = 0
            power_max[2] = 0
            write_en_flag = false
        end
    else
        if arm_flag then
            arm_flag = false
            write_en_flag = true
        end
    end
    power_max[2] = math.min(math.floor(value_min_max[1][1] * value_min_max[2][1]), 99999)
    if power_max[1] < power_max[2] then
        power_max[1] = power_max[2]
    end
    second[3] = getRtcTime()
    if second[2] ~= second[3] then
        second[2] = second[3]
        if arm_flag then
            second[1] = second[1] + 1
            total_second = total_second + 1
        end
    end
    minutes[1] = string.format("%02d", math.floor(second[1] % 3600 / 60))
    seconds[1] = string.format("%02d", second[1] % 3600 % 60)
    hours = string.format("%02d", math.floor(total_second / 3600))
    minutes[2] = string.format("%02d", math.floor(total_second % 3600 / 60))
    seconds[2] = string.format("%02d", total_second % 3600 % 60)
    if write_en_flag and fly_number < 57 and second[1] > 30 then
        -- Current frame: prepare data only, do not perform any file I/O
        fly_number = fly_number + 1
        log_info =
            string.format("%d", date_time.year) .. '/' ..
            string.format("%02d", date_time.mon) .. '/' ..
            string.format("%02d", date_time.day) .. '|' ..
            hours .. ':' .. minutes[2] .. ':' .. seconds[2] .. '|' ..
            string.format("%02d", fly_number) .. "\n"
        log_data[fly_number] =
            string.format("%02d", fly_number) .. '|' ..
            string.format("%02d", date_time.hour) .. ':' ..
            string.format("%02d", date_time.min) .. ':' ..
            string.format("%02d", date_time.sec) .. '|' ..
            minutes[1] .. ':' .. seconds[1] .. '|' ..
            string.format("%04d", math.max(0, value_min_max[4][1] - value_min_max[4][3])) .. '|' ..
            string.format("%03d", math.max(0, value_min_max[5][2] - value_min_max[5][1])) .. '|' ..
            string.format("%04d", value_min_max[3][2]) .. '|' ..
            string.format("%05.1f", value_min_max[2][2]) .. '|' ..
            string.format("%05d", power_max[1]) .. '|' ..
            string.format("%04.1f", value_min_max[1][2]) .. '|' ..
            string.format("%04.1f", value_min_max[1][3]) .. '|' ..
            string.format("%+04d", value_min_max[6][2]) .. '|' ..
            string.format("%+04d", value_min_max[6][3]) .. '|' ..
            string.format("%+04d", value_min_max[7][2]) .. '|' ..
            string.format("%+04d", value_min_max[7][3]) .. "|" ..
            string.format("%+04d", value_min_max[8][2]) .. '|' ..
            string.format("%+04d", value_min_max[8][3]) .. '|' ..
            string.format("%+04d", value_min_max[9][2]) .. '|' ..
            string.format("%+04d", value_min_max[9][3]) .. '|' ..
            string.format("%03d", value_min_max[10][2]) .. '|' ..
            string.format("%03d", value_min_max[10][3]) .. '|' ..
            string.format("%03d", value_min_max[11][2]) .. '|' ..
            string.format("%04.1f", value_min_max[12][2]) .. '|' ..
            string.format("%04.1f", value_min_max[12][3]) .. "\n"
        -- Keep only the references needed by the deferred main-log write.
        write_snapshot = {
            file_path  = file_path,
            log_info   = log_info,
            log_data   = log_data,
            fly_number = fly_number
        }
        write_state = 1
        write_en_flag = false
        -- Finalization work without heavy I/O runs in the trigger frame
        update_model_index(runtime_cache.model_name)
        session_flight_count = 0
        if current_model_name and current_model_name ~= "" then
            increment_total_flight_count(current_model_name)
            runtime_cache.total_flight_count = runtime_cache.total_flight_count + 1
            runtime_cache.daily_flight_count = fly_number
        end
    end
    -- Deferred write keeps file I/O outside the flight-finalization block.
    if write_state == 1 and write_snapshot then
        -- Frame 1: write the main log file (use table.concat to write historical entries in one shot)
        local f = io.open(write_snapshot.file_path, "w")
        if f then
            io.write(f, write_snapshot.log_info)
            if write_snapshot.fly_number > 1 then
                io.write(f, table.concat(write_snapshot.log_data, "", 1, write_snapshot.fly_number - 1))
            end
            io.write(f, write_snapshot.log_data[write_snapshot.fly_number])
            io.close(f)
        end
        write_snapshot = nil
        write_state = 0
    end
    -- Bottom information strip: pilot name and governor state
    local display_user_name = runtime_cache.pilot_name or DEFAULT_PILOT_NAME
    lcd.drawText(390, 400, display_user_name, CENTER + BOLD + square_color)
    lcd.drawText(550, 385, "Governor", BOLD + square_color)
    lcd.drawText(645, 385, gov_text, LEFT + BOLD + value_color)

    -- Left column: battery, temperature and current gauges
    local tmcu_value = (field_id[6][2] and value_min_max[6][1]) or 0
    local bat_percent = (field_id[5][2] and value_min_max[5][1]) or 0
    local battery_capacity = (field_id[4][2] and value_min_max[4][1]) or 0
    local current_value = (field_id[2][2] and value_min_max[2][1]) or 0
    local current_arm_status = (field_id[13][2] and value_min_max[13][1]) or 0
    local current_is_armed = (current_arm_status == 1 or current_arm_status == 3)

    update_low_battery_alert(widget, bat_percent, current_is_armed, field_id[5][2] and telemetry_initialized)

    draw_gauge_meter(125, 450, tmcu_value, 100, 100, value_color, square_color)
    lcd.drawText(80, 400, "°C", square_color)

    draw_digital_display(93, 170, battery_capacity, 4, 0, 14, value_color)
    lcd.drawText(163, 168, "mah", square_color)
    draw_digital_display(93, 230, bat_percent, 3, 0, 30, value_color)
    lcd.drawText(201, 248, "%", square_color)
    draw_ring_progress(150, 205, bat_percent, 100, 120)

    if current_value > current_flight_max_current then
        current_flight_max_current = current_value
    end
    draw_power_gauge(217, 395, 70, current_value, 300, square_color, value_color)
    draw_ring_progress(217, 395, current_flight_max_current, 300, 80)

    -- Center column: RPM and voltages
    local rpm_value = (field_id[3][2] and value_min_max[3][1]) or 0
    local battery_voltage = (field_id[1][2] and value_min_max[1][1]) or 0
    local vcel_voltage = (field_id[15][2] and value_min_max[15][1]) or 0
    local bec_voltage = (field_id[12][2] and value_min_max[12][1]) or 0

    draw_digital_display(320, 115, rpm_value, 4, 0, 35, value_color)
    lcd.drawText(500, 156, "rpm", CENTER + VCENTER + square_color)

    lcd.drawText(320, 210, "Volt", BOLD + square_color)
    draw_digital_display(380, 210, battery_voltage, 2, 2, 21, value_color)
    lcd.drawText(480, 218, "V", square_color)

    lcd.drawText(320, 269, "Vcel", BOLD + square_color)
    draw_digital_display(380, 269, vcel_voltage, 2, 2, 21, value_color)
    lcd.drawText(480, 277, "V", square_color)

    lcd.drawText(320, 330, "Bec", BOLD + square_color)
    draw_digital_display(380, 330, bec_voltage, 2, 2, 21, value_color)
    lcd.drawText(480, 338, "V", square_color)

    -- Right column: flight counters and timer
    local flight_minutes = math.floor(second[1] % 3600 / 60)
    local flight_seconds = second[1] % 3600 % 60
    local total_all_flights = telemetry_initialized and runtime_cache.total_flight_count or 0
    local total_flight_count = runtime_cache.daily_flight_count + session_flight_count
    lcd.drawText(554, 125, "Flight", BOLD + square_color)
    draw_digital_display(620, 130, total_all_flights, 4, 0, 13, value_color)
    draw_digital_display(715, 130, math.max(0, total_flight_count), 3, 0, 13, value_color)

    lcd.drawText(553, 90, "Time", BOLD + square_color)
    draw_time_display(610, 70, flight_minutes, flight_seconds, 30, value_color)
end
return {
    name = NAME,
    options = options,
    create = create,
    update = update,
    refresh = refresh,
    background = background
}
