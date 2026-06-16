-- Hammerspoon HUD and global hotkey for the macOS STT installer.

local sourcePath = debug.getinfo(1, "S").source:gsub("^@", "")
local scriptDir = sourcePath:match("^(.*)/[^/]+$") or (os.getenv("HOME") .. "/.local/share/stt")
local sttScript = scriptDir .. "/stt-global.sh"
local sttPidFile = "/tmp/stt-recording.pid"
local sttAudioFile = "/tmp/stt-recording.wav"
local phaseFile = "/tmp/stt-overlay-phase"
local logFile = scriptDir .. "/stt-overlay.log"

local taskRunning = false
local currentTask = nil

local overlay = {
    canvas = nil,
    timer = nil,
    hideTimer = nil,
    mode = "idle",
    phase = 0,
    width = 190,
    height = 46,
    levels = {},
}

local colors = {
    shadow = { red = 0, green = 0, blue = 0, alpha = 0.34 },
    rec = { red = 0.08, green = 0.95, blue = 0.68, alpha = 1 },
    whisper = { red = 0.20, green = 0.64, blue = 1.00, alpha = 1 },
    llm = { red = 0.78, green = 0.54, blue = 1.00, alpha = 1 },
    ok = { red = 0.30, green = 0.96, blue = 0.42, alpha = 1 },
    err = { red = 1.00, green = 0.26, blue = 0.24, alpha = 1 },
}

local icon = { start = 1, count = 10 }
local wave = { start = 11, count = 22 }
local spinner = { start = 33, count = 12 }
local postIcon = { start = 45, count = 6 }

local function log(message)
    local file = io.open(logFile, "a")
    if not file then
        return
    end
    file:write(os.date("[%Y-%m-%dT%H:%M:%S%z] "), message, "\n")
    file:close()
end

local function color(colorValue, alpha)
    return {
        red = colorValue.red,
        green = colorValue.green,
        blue = colorValue.blue,
        alpha = alpha == nil and colorValue.alpha or alpha,
    }
end

local function commandSucceeds(command)
    local _, ok = hs.execute(command, true)
    return ok == true
end

local function readTextFile(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local value = file:read("*l")
    file:close()
    return value
end

local function removePhaseFile()
    os.remove(phaseFile)
end

local function currentPhase()
    local value = readTextFile(phaseFile)
    if value == "whisper" or value == "llm" then
        return value
    end
    return nil
end

local function sttIsRecording()
    local pid = readTextFile(sttPidFile)
    if not pid or not pid:match("^%d+$") then
        return false
    end
    return commandSucceeds("/bin/kill -0 " .. pid .. " 2>/dev/null")
end

local function sttProcessRunning()
    return commandSucceeds("/usr/bin/pgrep -f 'stt-global\\.sh|stt-transcribe\\.sh|stt-postprocess\\.sh' >/dev/null 2>&1")
end

local function ensureLevels()
    for i = 1, wave.count do
        overlay.levels[i] = overlay.levels[i] or 0
    end
end

local function readAudioLevels()
    ensureLevels()

    local file = io.open(sttAudioFile, "rb")
    if not file then
        return overlay.levels
    end

    local size = file:seek("end")
    if not size or size <= 44 then
        file:close()
        return overlay.levels
    end

    local maxBytes = wave.count * 480
    local available = size - 44
    local readBytes = math.min(available, maxBytes)
    readBytes = readBytes - (readBytes % 2)

    if readBytes <= 0 then
        file:close()
        return overlay.levels
    end

    file:seek("set", size - readBytes)
    local data = file:read(readBytes) or ""
    file:close()

    local sampleCount = math.floor(#data / 2)
    if sampleCount <= 0 then
        return overlay.levels
    end

    local samplesPerBucket = math.max(1, math.floor(sampleCount / wave.count))
    local targets = {}

    for bucket = 1, wave.count do
        local sum = 0
        local peak = 0
        local countSamples = 0
        local startSample = ((bucket - 1) * samplesPerBucket) + 1
        local endSample = bucket == wave.count and sampleCount or math.min(sampleCount, bucket * samplesPerBucket)

        for sampleIndex = startSample, endSample do
            local byteIndex = ((sampleIndex - 1) * 2) + 1
            local lo = data:byte(byteIndex) or 0
            local hi = data:byte(byteIndex + 1) or 0
            local sample = lo + (hi * 256)
            if sample >= 32768 then
                sample = sample - 65536
            end

            local normalized = math.abs(sample) / 32768
            peak = math.max(peak, normalized)
            sum = sum + (normalized * normalized)
            countSamples = countSamples + 1
        end

        local rms = countSamples > 0 and math.sqrt(sum / countSamples) or 0
        local voiceLevel = math.max(rms * 1.45, peak * 0.46)
        local gated = math.max(0, voiceLevel - 0.003)
        targets[bucket] = math.min(1, math.pow(gated * 31.0, 0.52))
    end

    for i = 1, wave.count do
        overlay.levels[i] = (overlay.levels[i] * 0.28) + ((targets[i] or 0) * 0.72)
    end

    return overlay.levels
end

local function positionOverlay()
    if not overlay.canvas then
        return
    end

    local frame = hs.screen.mainScreen():fullFrame()
    overlay.canvas:frame({
        x = frame.x + ((frame.w - overlay.width) / 2),
        y = frame.y + 26,
        w = overlay.width,
        h = overlay.height,
    })
end

local function setElement(index, props)
    for key, value in pairs(props) do
        overlay.canvas[index][key] = value
    end
end

local function hideRange(startIndex, count)
    for i = startIndex, startIndex + count - 1 do
        if overlay.canvas[i] then
            overlay.canvas[i].fillColor = color(colors.rec, 0)
            overlay.canvas[i].strokeColor = color(colors.rec, 0)
        end
    end
end

local function hidePostIcon()
    for i = postIcon.start, postIcon.start + postIcon.count - 1 do
        if overlay.canvas[i] then
            overlay.canvas[i].fillColor = color(colors.whisper, 0)
        end
    end
end

local function ensureOverlay()
    if overlay.canvas then
        positionOverlay()
        return
    end

    overlay.canvas = hs.canvas.new({ x = 0, y = 0, w = overlay.width, h = overlay.height })
    overlay.canvas:level(hs.drawing.windowLevels.overlay)
    overlay.canvas:behavior({ "canJoinAllSpaces", "stationary" })

    for i = 1, icon.count do
        overlay.canvas[icon.start + i - 1] = {
            type = "rectangle",
            action = "fill",
            frame = { x = 0, y = 0, w = 1, h = 1 },
            roundedRectRadii = { xRadius = 1, yRadius = 1 },
            fillColor = color(colors.rec, 0),
        }
    end

    for i = 1, wave.count do
        overlay.canvas[wave.start + i - 1] = {
            type = "rectangle",
            action = "fill",
            frame = { x = 42 + ((i - 1) * 6), y = 22, w = 3, h = 2 },
            roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
            fillColor = color(colors.rec, 0),
        }
    end

    for i = 1, spinner.count do
        overlay.canvas[spinner.start + i - 1] = {
            type = "oval",
            action = "fill",
            frame = { x = 92, y = 21, w = 4, h = 4 },
            fillColor = color(colors.whisper, 0),
        }
    end

    for i = 1, postIcon.count do
        overlay.canvas[postIcon.start + i - 1] = {
            type = "oval",
            action = "fill",
            frame = { x = 0, y = 0, w = 1, h = 1 },
            fillColor = color(colors.whisper, 0),
        }
    end

    positionOverlay()
end

local function drawMicIcon()
    hidePostIcon()
    hideRange(icon.start, icon.count)

    setElement(1, {
        type = "rectangle",
        action = "fill",
        frame = { x = 13, y = 7, w = 14, h = 22 },
        roundedRectRadii = { xRadius = 7, yRadius = 7 },
        fillColor = color(colors.shadow, 0.45),
    })
    setElement(2, {
        type = "rectangle",
        action = "fill",
        frame = { x = 14, y = 6, w = 12, h = 21 },
        roundedRectRadii = { xRadius = 6, yRadius = 6 },
        fillColor = color(colors.rec, 1),
    })
    setElement(3, {
        type = "rectangle",
        action = "fill",
        frame = { x = 18, y = 27, w = 4, h = 8 },
        roundedRectRadii = { xRadius = 2, yRadius = 2 },
        fillColor = color(colors.rec, 0.92),
    })
    setElement(4, {
        type = "rectangle",
        action = "fill",
        frame = { x = 12, y = 35, w = 16, h = 3 },
        roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
        fillColor = color(colors.rec, 0.92),
    })
end

local function drawWhisperIcon()
    hideRange(icon.start, icon.count)
    hidePostIcon()

    setElement(postIcon.start, {
        frame = { x = 9, y = 17, w = 15, h = 15 },
        fillColor = color(colors.whisper, 0.95),
    })
    setElement(postIcon.start + 1, {
        frame = { x = 17, y = 8, w = 20, h = 20 },
        fillColor = color(colors.whisper, 0.95),
    })
    setElement(postIcon.start + 2, {
        frame = { x = 28, y = 18, w = 14, h = 14 },
        fillColor = color(colors.whisper, 0.95),
    })
end

local function drawLlmIcon()
    hideRange(icon.start, icon.count)
    hidePostIcon()

    local points = {
        { x = 15, y = 11, size = 9, alpha = 0.86 },
        { x = 29, y = 14, size = 11, alpha = 1.00 },
        { x = 20, y = 29, size = 9, alpha = 0.90 },
        { x = 9, y = 24, size = 7, alpha = 0.70 },
    }

    for i, point in ipairs(points) do
        setElement(postIcon.start + i - 1, {
            frame = { x = point.x, y = point.y, w = point.size, h = point.size },
            fillColor = color(colors.llm, point.alpha),
        })
    end
end

local function drawErrorIcon()
    hideRange(icon.start, icon.count)
    hidePostIcon()
    setElement(postIcon.start, {
        frame = { x = 12, y = 10, w = 22, h = 22 },
        fillColor = color(colors.err, 0.95),
    })
end

local function drawIconForMode(mode)
    if mode == "recording" then
        drawMicIcon()
    elseif mode == "whisper" then
        drawWhisperIcon()
    elseif mode == "llm" then
        drawLlmIcon()
    else
        drawErrorIcon()
    end
end

local function renderWave()
    hideRange(spinner.start, spinner.count)

    local levels = readAudioLevels()
    local centerY = 23
    for i = 1, wave.count do
        local level = levels[i] or 0
        local height = 3 + (level * 32)
        local alpha = 0.10 + (level * 0.90)
        setElement(wave.start + i - 1, {
            frame = { x = 45 + ((i - 1) * 6), y = centerY - (height / 2), w = 3, h = height },
            fillColor = color(colors.rec, alpha),
        })
    end
end

local function renderSpinner(mode)
    hideRange(wave.start, wave.count)

    local spinColor = mode == "llm" and colors.llm or colors.whisper
    local centerX = 100
    local centerY = 23
    local radius = 15
    local active = math.floor(overlay.phase * 9)

    for i = 1, spinner.count do
        local angle = ((i - 1) / spinner.count) * (math.pi * 2)
        local rank = ((i + active) % spinner.count) + 1
        local alpha = 0.13 + ((rank / spinner.count) * 0.87)
        setElement(spinner.start + i - 1, {
            frame = {
                x = centerX + (math.cos(angle) * radius),
                y = centerY + (math.sin(angle) * radius),
                w = 4,
                h = 4,
            },
            fillColor = color(spinColor, alpha),
        })
    end
end

local function renderOverlay()
    if not overlay.canvas then
        return
    end

    overlay.phase = overlay.phase + 0.11

    local phase = currentPhase()
    if phase and (overlay.mode == "whisper" or overlay.mode == "llm") then
        overlay.mode = phase
    end

    drawIconForMode(overlay.mode)

    if overlay.mode == "recording" then
        renderWave()
    elseif overlay.mode == "whisper" or overlay.mode == "llm" then
        renderSpinner(overlay.mode)
    else
        hideRange(wave.start, wave.count)
        hideRange(spinner.start, spinner.count)
    end
end

function overlay.show(mode)
    ensureOverlay()

    if overlay.hideTimer then
        overlay.hideTimer:stop()
        overlay.hideTimer = nil
    end

    overlay.mode = mode
    renderOverlay()
    overlay.canvas:show()

    if not overlay.timer then
        overlay.timer = hs.timer.doEvery(0.05, renderOverlay)
    elseif not overlay.timer:running() then
        overlay.timer:start()
    end
end

function overlay.hide()
    if overlay.timer then
        overlay.timer:stop()
    end
    if overlay.canvas then
        overlay.canvas:hide()
    end
    overlay.mode = "idle"
end

function overlay.flash(mode, seconds)
    overlay.show(mode)
    overlay.hideTimer = hs.timer.doAfter(seconds or 0.9, overlay.hide)
end

local function resetSttUi(reason)
    taskRunning = false
    currentTask = nil
    removePhaseFile()
    overlay.hide()
    log("reset ui reason=" .. tostring(reason))
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- mode selects post-processing on STOP: "full" (LLM, source language),
-- "raw" (no LLM), "english" (LLM + translate to English). The mode of the
-- press that STOPS recording wins; the start press only begins recording.
local function launchSttToggle(mode)
    mode = mode or "full"
    local wasRecording = sttIsRecording()
    local action = wasRecording and "stop" or "start"

    log("trigger action=" .. action .. " mode=" .. mode .. " taskRunning=" .. tostring(taskRunning))

    if taskRunning then
        if not sttProcessRunning() and not sttIsRecording() then
            log("clearing stale task flag")
            taskRunning = false
            currentTask = nil
        else
            overlay.show(currentPhase() or "whisper")
            return
        end
    end

    removePhaseFile()
    taskRunning = true

    if wasRecording then
        overlay.show("whisper")
    else
        overlay.show("recording")
    end

    local command = "STT_MODE=" .. shellQuote(mode) .. " STT_NOTIFICATIONS=0 STT_PHASE_FILE=" .. shellQuote(phaseFile) .. " exec " .. shellQuote(sttScript)
    currentTask = hs.task.new("/bin/bash", function(exitCode)
        log("task exit action=" .. action .. " exitCode=" .. tostring(exitCode))
        taskRunning = false
        currentTask = nil

        if wasRecording then
            removePhaseFile()
            if exitCode == 0 then
                overlay.hide()
            else
                overlay.flash("error", 1.4)
            end
        elseif exitCode == 0 and sttIsRecording() then
            overlay.show("recording")
        else
            overlay.flash("error", 1.4)
        end
    end, function(_, stdout, stderr)
        if stdout and stdout ~= "" then
            log("stdout " .. stdout:gsub("%s+$", ""))
        end
        if stderr and stderr ~= "" then
            log("stderr " .. stderr:gsub("%s+$", ""))
        end
        return true
    end, {
        "-lc",
        command,
    })

    if not currentTask:start() then
        log("task failed to start action=" .. action)
        taskRunning = false
        currentTask = nil
        overlay.flash("error", 1.4)
        return
    end

    if not wasRecording then
        hs.timer.doAfter(4, function()
            if taskRunning and not sttProcessRunning() then
                log("start callback watchdog reset")
                taskRunning = false
                currentTask = nil
                if sttIsRecording() then
                    overlay.show("recording")
                else
                    overlay.flash("error", 1.4)
                end
            end
        end)
    end
end

STTOverlay = overlay
STTTrigger = launchSttToggle
STTReset = resetSttUi
STTWaveLevels = readAudioLevels

-- Cmd+Shift+Space  : full transcript with LLM cleanup (source language)
-- Ctrl+Shift+Space : raw transcript, no LLM (text replacements still apply)
-- Cmd+Alt+Space    : LLM cleanup, output translated to English
hs.hotkey.bind({ "cmd", "shift" }, "space", function() launchSttToggle("full") end)
hs.hotkey.bind({ "ctrl", "shift" }, "space", function() launchSttToggle("raw") end)
hs.hotkey.bind({ "cmd", "alt" }, "space", function() launchSttToggle("english") end)
