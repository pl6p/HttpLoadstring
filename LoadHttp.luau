local mloadstring = require(script.Loadstring)
local HttpService = game:GetService("HttpService")
local lz4 = require(script.LZ4)
local cache = {}

_LOADHTTP_DEBUG = false
_LOADHTTP_MAX_SIZE = 20
_LOADHTTP_CLEAR_CACHE = false
_LOADHTTP_COMPRESS = false
_LOADHTTP_SAVE_SOURCE = false
_LOADHTTP_SHOW_PERFORMANCE = false

local function log(...)
	if _LOADHTTP_DEBUG then
		print(...)
	end
end

local function fmt_time(t)
	return string.format("%.4f", t)
end

local function bytesize(bytes)
	if bytes >= 1024 * 1024 then
		return string.format("%.2f MB", bytes / (1024 * 1024))
	elseif bytes >= 1024 then
		return string.format("%.2f KB", bytes / 1024)
	else
		return string.format("%d B", bytes)
	end
end

-- Example loadhttp("https://mycoolsource.xyz/helloworld.lua")
return function(url, env)
	if not url or url == "" then
		error("LoadHttp: url is empty")
		return nil, "no url"
	end

	env = env or getfenv(2)

	--check cache
	if not _LOADHTTP_CLEAR_CACHE then
		local cached = cache[url]
		if cached then
			log("~cache hit~ (picking script from cache)")
			log("~cache hit~ (" .. bytesize(cached.size) .. ")")
			local start_time = os.clock()
			local ok, result = pcall(cached.func, env)
			local exec_time = os.clock() - start_time
			if ok then
				log(string.format("exec time: %.6f sec", exec_time))
				if _LOADHTTP_SHOW_PERFORMANCE then
					log("~performance: 100% (from cache)~")
				end
				return result
			else
				log("exec error: " .. tostring(result))
				return nil, result
			end
		else
			log("~cache miss~ (picking script from scratch)")
		end
	end

	--loading 
	log("~loading~")
	local load_start = os.clock()
	local ok, source = pcall(function()
		return HttpService:GetAsync(url, false) 
	end)
	local load_time = os.clock() - load_start

	if not ok then
		log("http error: " .. tostring(source))
		return nil, source
	end

	if type(source) ~= "string" then
		log("response is not a string (got " .. type(source) .. ")")
		return nil, "invalid response type"
	end

	local size = #source
	local max_size_bytes = _LOADHTTP_MAX_SIZE * 1024 * 1024

	if size > max_size_bytes then
		log(string.format("script too large (%s, max %d MB)", bytesize(size), _LOADHTTP_MAX_SIZE))
		return nil, "script too large"
	end

	if size == 0 then
		log("empty response")
		return nil, "empty response"
	end

	log(string.format("loaded %s (%s) in %s sec", bytesize(size), size .. " bytes", fmt_time(load_time)))

	-- compress
	local compressed = source
	local compress_time = 0
	if _LOADHTTP_COMPRESS and size > 128 then
		local compress_start = os.clock()
		local compress_ok, result = pcall(lz4.compress, source)
		compress_time = os.clock() - compress_start

		if compress_ok and result then
			local new_size = #result
			if new_size < size then
				compressed = result
				log(string.format("compressed from %s to %s (%.1f%%) in %s sec", 
					bytesize(size), 
					bytesize(new_size), 
					(new_size / size) * 100,
					fmt_time(compress_time)))
			else
				log(string.format("compression not beneficial: %s -> %s", 
					bytesize(size), bytesize(new_size)))
			end
		else
			log("compression failed")
		end
	elseif _LOADHTTP_COMPRESS and size <= 128 then
		log("skipping compression: data too small (" .. bytesize(size) .. ")")
	end

	--compile
	log("~compiling~ (" .. bytesize(size) .. ")")
	local compile_start = os.clock()
	local compiled, err = mloadstring(source, env)
	local compile_time = os.clock() - compile_start

	if not compiled then
		log("compile error: " .. tostring(err))
		return nil, err
	end

	log(string.format("compile time: %.6f sec", compile_time))

	--saving cache
	if not _LOADHTTP_CLEAR_CACHE then
		if _LOADHTTP_SAVE_SOURCE then
			cache[url] = {
				func = compiled,
				size = size,
				compressed = compressed
			}
		else
			cache[url] = {
				func = compiled,
				size = size
			}
		end
	end

	--running
	log("~running~ (" .. bytesize(size) .. ")")
	local exec_start = os.clock()
	local ok2, result = pcall(compiled, env)
	local exec_time = os.clock() - exec_start

	if not ok2 then
		log("exec error: " .. tostring(result))
		return nil, result
	end

	log(string.format("^^^^^^^^^^^^^^^^^ executed from " .. url .. " in: %.6f sec", exec_time))
	log("~done~ (" .. bytesize(size) .. ")")

	-- performance
	if _LOADHTTP_SHOW_PERFORMANCE then
		local total_time = load_time + compile_time + exec_time + compress_time
		if total_time > 0 then
			local load_percent = (load_time / total_time) * 100
			local compile_percent = (compile_time / total_time) * 100
			local exec_percent = (exec_time / total_time) * 100

			local performance_score = 100 - ((load_percent * 0.3) + (compile_percent * 0.4) + (exec_percent * 0.3))
			performance_score = math.max(0, math.min(100, performance_score))

			if performance_score >= 90 then
				log(string.format("~performance: %.1f%% (excellent)~", performance_score))
			elseif performance_score >= 70 then
				log(string.format("~performance: %.1f%% (good)~", performance_score))
			elseif performance_score >= 50 then
				log(string.format("~performance: %.1f%% (ok)~", performance_score))
			else
				log(string.format("~performance: %.1f%% (slow)~", performance_score))
			end

			log(string.format("~load: %.1f%%, compile: %.1f%%, exec: %.1f%%~", 
				load_percent, compile_percent, exec_percent))
		end
	end

	return result
end
