--[[
    UI 中文化 · 通用版（Universal Roblox UI Translator）
    English -> 简体中文，实时翻译任意注入脚本的菜单 / 游戏 HUD

    用法：执行即可，没有其他步骤。

    核心机制：
      1) 识别  扫描 gethui()/CoreGui，用「文本量 + 菜单词命中」打分找出脚本菜单，
               Roblox 自带 UI 靠黑名单排除
      2) 词表  高频词本地翻，零延迟。EXACT_PAIRS 只保留核心词，不堆长句
      3) 机翻  词表翻不出来的自动排队走在线翻译：google -> mymemory -> youdao
               逐个探测，哪个通用哪个；翻好即时回填界面
               网络不通就静默退回纯词表模式，不影响其余功能
      4) 跟随  切标签 / 重开面板 / 脚本自己改文字，都会自动补翻
      5) 可逆  右上角「中 / EN」按钮一键切换，原文全部缓存

    运行后可用：
      UIT_CN.restore()              还原英文
      UIT_CN.enable() / disable()   重新翻译 / 暂停
      UIT_CN.rescan()               立即重扫
      UIT_CN.diagnose(true)         诊断：每个界面为什么没翻 + 实际英文文本
      UIT_CN.autoStats()            自动翻译状态（后端 / 缓存 / 队列 / 成败）
      UIT_CN.auto(false)            关闭自动翻译，只走词表
      UIT_CN.setProvider("youdao")  指定翻译后端
      UIT_CN.addPairs({ {"Auto Fish","自动钓鱼"} })   追加词条
      UIT_CN.stop()                 停止并移除按钮

    界面没翻？三步排查：
      1) 跑 diagnose()，看卡在哪一条：文本数不够 / 菜单分不够 / 3D 标签没开
      2) 菜单分不够 —— 往 MARKERS 补几个该界面里的高频词
      3) 干脆不认 —— CONFIG.forceInclude = { "windui", "onyx" }，填名字片段必翻

    所有开关都在下面 CONFIG 里，改完重新执行即可。
]]

local CONFIG = {
    autoApply        = true,   -- 执行后立即翻译
    showToggle       = true,   -- 显示浮动「中/EN」按钮
    translatePlayerGui = false, -- true = 连游戏本身 HUD 一起翻
    watchNewUI       = true,   -- 监听后续新建 / 重建的界面
    rescanSeconds    = 180,    -- 兜底重扫持续时间（秒）；手机别太长
    rescanInterval   = 1.5,    -- 兜底重扫间隔（秒），会自适应变慢
    rescanMaxGap     = 6,      -- 兜底重扫间隔上限（秒）
    minTextsForMenu  = 8,      -- 判定菜单：GUI 内文本元素下限
                               --   原 24 太高：卡片式/小面板菜单（如 22 个文本的注入面板）会被整体跳过
    minMenuScore     = 1,      -- 判定菜单：命中菜单特征词的数量下限
                               --   原 3 太高：那是按 FPS 外挂词表定的，赛车/模拟/经营类脚本命中不到
    bigTextsForMenu  = 80,     -- 文本多到一定程度直接判为菜单（不做严格模式）
    strictNoMixed    = true,   -- 严格模式：译文里还有没翻掉的英文词就整条保留原文（不出半中半英）
    maxLeftRatio     = 0.4,    -- 兼容旧配置，留作参考
    includeNames     = {},     -- 强制纳入的 GUI 名（小写子串），如 { "hub", "menu" }
    extraExclude     = {},     -- 额外排除的 GUI 名（小写）
    verbose          = true,

    -- 目标 GUI 名：不知道名字时先跑 getgenv().UIT_CN.diagnose() 看一份清单再填这里
    -- 填了之后该 GUI 无条件翻译，绕过所有打分逻辑（最保险的做法）
    forceInclude     = {},

    -- 是否连游戏自己的 3D 世界标签（BillboardGui / SurfaceGui）一起翻
    -- 例：车行招牌、箱子标签；默认 off，避免翻到满地图的广告牌
    includeBillboard = false,

    -- ===== 自动翻译（词表没覆盖的文本，走在线翻译）=====
    -- 打开后不再需要手动往 EXACT_PAIRS 加词条：词表命中就本地翻（快），
    -- 没命中就排队调用在线接口，结果写进缓存并立即应用到界面上。
    autoTranslate   = true,
    apiProvider     = "auto",   -- auto | google | mymemory | youdao
    apiBatch        = 12,       -- 每批处理几条（google 支持换行合并，一次请求翻一批）
    apiInterval     = 0.12,     -- 每批之间的间隔（秒）
    apiTimeoutMs    = 8000,
    apiRetries      = 1,
    maxQueue        = 600,      -- 待翻译队列上限
    maxTextLen      = 160,      -- 超过这个长度的不进自动翻译（长句机翻很烂）
    skipPlayerNames = true,     -- 跳过玩家名，不翻成人名乱码

    -- ===== 移动端 / 执行器兼容参数 =====
    frameBudget      = 0.012,  -- 单帧扫描时间预算（秒），越小越不卡
    cacheSeconds     = 3,      -- GUI 判定结果缓存时间（秒），过期才重新判定
    usePlayerGuiFallback = true, -- 隐藏容器里一个菜单都没找到时，退一步扫 PlayerGui
    toggleSize       = nil,    -- 手动指定按钮尺寸 {w, h}，nil = 触屏自动放大
}

----------------------------------------------------------------
-- 0. 执行器兼容层（Delta / Android 优先）
----------------------------------------------------------------
-- 说明：不同执行器暴露的全局函数、可写入的 GUI 父级都不同。
--       这里全部走探测 + pcall，任何一步失败都只是降级，不会中断脚本。

local ENV = (type(getgenv) == "function" and getgenv()) or _G
local PlayersSvc = game:GetService("Players")
local UserInput
pcall(function() UserInput = game:GetService("UserInputService") end)

local function safeGet(fn, default)
    local ok, v = pcall(fn)
    if ok and v ~= nil then return v end
    return default
end

local function isInst(v)
    local ok, r = pcall(function() return typeof(v) == "Instance" end)
    return ok and r == true
end

-- 等待 LocalPlayer 就绪（Delta 在加载界面注入时可能为 nil）
-- 带缓存 + 失败退避，避免每次重扫都白等 3 秒
local playerCache, playerFailAt = nil, nil

local function getLocalPlayer(timeout)
    if isInst(playerCache) and playerCache.Parent then return playerCache end
    local p = PlayersSvc.LocalPlayer
    if p then playerCache = p; return p end
    if playerFailAt and (os.clock() - playerFailAt) < 15 then return nil end

    local t0 = os.clock()
    local limit = timeout or 3
    while os.clock() - t0 < limit do
        task.wait(0.2)
        p = PlayersSvc.LocalPlayer
        if p then playerCache = p; return p end
    end
    playerFailAt = os.clock()
    return nil
end

local function getPlayerGui()
    local plr = getLocalPlayer(3)
    if not plr then return nil end
    local pg = safeGet(function() return plr:FindFirstChildOfClass("PlayerGui") end)
    if pg then return pg end
    return safeGet(function() return plr:WaitForChild("PlayerGui", 5) end)
end

-- 隐藏 GUI 容器：依次尝试各家执行器的接口
local GUI_PARENT_NAME = "未挂载"

local function tryHiddenRoot()
    local names = { "gethui", "get_hidden_gui", "getHiddenGui", "gethiddenui" }
    for _, n in ipairs(names) do
        local f = ENV[n] or rawget(_G, n)
        if type(f) == "function" then
            local ok, h = pcall(f)
            if ok and isInst(h) then
                GUI_PARENT_NAME = n .. "()"
                return h
            end
        end
    end
    return nil
end

local function probeParent(parent)
    if not isInst(parent) then return false end
    local probe = Instance.new("ScreenGui")
    probe.Name = "UIT_CN_Probe"
    probe.ResetOnSpawn = false
    local ok = pcall(function() probe.Parent = parent end)
    local ok2 = ok and safeGet(function() return probe.Parent == parent end, false)
    pcall(function() probe:Destroy() end)
    return ok2 == true
end

-- 解析可用父级：gethui -> get_hidden_gui -> CoreGui(探测写入) -> PlayerGui
local function resolveGuiParent()
    local h = tryHiddenRoot()
    if h then return h end

    local cg = safeGet(function() return game:GetService("CoreGui") end)
    if cg and probeParent(cg) then
        GUI_PARENT_NAME = "CoreGui"
        return cg
    end

    local pg = getPlayerGui()
    if pg then
        GUI_PARENT_NAME = "PlayerGui"
        return pg
    end

    GUI_PARENT_NAME = "无可用父级"
    return nil
end


----------------------------------------------------------------
-- 1. 词库：通用界面 / 功能 / 设置术语
----------------------------------------------------------------
local EXACT_PAIRS = {
    -- 只放「高频 + 机翻容易翻错」的核心词，其余全部交给自动翻译引擎。
    -- 不要再往这里堆长句了：实测长句机翻质量比手写词条还自然，
    -- 堆词条只会让文件膨胀，却换不来更好的效果。

    -- 菜单骨架
    { "Menu", "菜单" }, { "Main", "主界面" }, { "Home", "首页" }, { "General", "常规" },
    { "Settings", "设置" }, { "Options", "选项" }, { "Config", "配置" }, { "Advanced", "高级" },
    { "Misc", "杂项" }, { "Info", "信息" }, { "About", "关于" }, { "Version", "版本" },
    { "Close", "关闭" }, { "Exit", "退出" }, { "Back", "返回" }, { "Next", "下一步" },
    { "Confirm", "确认" }, { "Cancel", "取消" }, { "Apply", "应用" }, { "Save", "保存" },
    { "Load", "加载" }, { "Reset", "重置" }, { "Default", "默认" }, { "Restore", "恢复" },
    { "Yes", "是" }, { "No", "否" }, { "On", "开" }, { "Off", "关" },
    { "Enable", "启用" }, { "Disable", "禁用" }, { "Enabled", "已启用" }, { "Disabled", "已禁用" },
    { "Auto", "自动" }, { "Manual", "手动" }, { "Toggle", "开关" }, { "Option", "选项" },

    -- 货币 / 进度
    { "Level", "等级" }, { "Lvl", "等级" }, { "Exp", "经验" }, { "XP", "经验" },
    { "Coins", "金币" }, { "Coin", "金币" }, { "Gems", "宝石" }, { "Gem", "宝石" },
    { "Cash", "现金" }, { "Money", "金钱" }, { "Credits", "积分" }, { "Credit", "积分" },
    { "Tokens", "代币" }, { "Balance", "余额" }, { "Price", "价格" }, { "Cost", "花费" },
    { "Total", "总计" }, { "Reward", "奖励" }, { "Rewards", "奖励" }, { "Claim", "领取" },
    { "Collect", "领取" }, { "Progress", "进度" }, { "Rank", "排名" }, { "Streak", "连胜" },

    -- 商店 / 背包 / 物品
    { "Shop", "商店" }, { "Store", "商店" }, { "Market", "市场" }, { "Crate", "箱子" },
    { "Inventory", "背包" }, { "Backpack", "背包" }, { "Item", "物品" }, { "Items", "物品" },
    { "Buy", "购买" }, { "Sell", "出售" }, { "Purchase", "购买" }, { "Trade", "交易" },
    { "Equip", "装备" }, { "Unequip", "卸下" }, { "Upgrade", "升级" }, { "Unlock", "解锁" },

    -- 玩法通用
    { "Start", "开始" }, { "Stop", "停止" }, { "Pause", "暂停" }, { "Resume", "继续" },
    { "Restart", "重新开始" }, { "Ready", "准备" }, { "Leave", "离开" }, { "Join", "加入" },
    { "Map", "地图" }, { "Mode", "模式" }, { "Stage", "关卡" }, { "Mission", "任务" },
    { "Quest", "任务" }, { "Challenge", "挑战" }, { "Score", "得分" },

    -- 赛车 / 驾驶（实测高频，本地翻省请求）
    { "Race", "比赛" }, { "Racing", "比赛" }, { "Rally", "拉力赛" }, { "Car", "车辆" },
    { "Cars", "车辆" }, { "Vehicle", "载具" }, { "Drive", "驾驶" }, { "Driving", "驾驶" },
    { "Speed", "速度" }, { "Boost", "加速" }, { "Nitro", "氮气" }, { "Drift", "漂移" },
    { "Lap", "圈" }, { "Laps", "圈" }, { "Checkpoint", "检查点" }, { "Finish", "终点" },
    { "Position", "名次" }, { "Garage", "车库" }, { "Engine", "引擎" }, { "Tires", "轮胎" },

    -- 玩家 / 战斗 / 数值
    { "Player", "玩家" }, { "Players", "玩家" }, { "Team", "队伍" }, { "Health", "生命" },
    { "Target", "目标" }, { "Targets", "目标" }, { "Self", "自身" }, { "Friend", "好友" },
    { "Damage", "伤害" }, { "Status", "状态" }, { "Online", "在线" }, { "Ping", "延迟" },
    { "Distance", "距离" }, { "Radius", "半径" }, { "Range", "范围" }, { "Amount", "数量" },
    { "Value", "数值" }, { "Interval", "间隔" }, { "Delay", "延迟" }, { "Keybind", "按键" },

    -- 游戏术语修正：机翻在这些词上必错（Auto→汽车、Mob→暴民、Farming→耕作）
    -- 词表优先于机翻，所以这类高频术语写在这里就等于强行纠正译法
    { "Auto", "自动" }, { "Farm", "刷取" }, { "Farming", "刷取" },
    { "Autofarm", "自动刷取" }, { "Mob", "怪物" }, { "Mobs", "怪物" },
    { "Monster", "怪物" }, { "Monsters", "怪物" }, { "Enemy", "敌人" },
    { "Attack", "攻击" }, { "Summon", "召唤" }, { "Moves", "移动" },
    { "AFK", "挂机" }, { "Refresh", "刷新" }, { "Selected", "已选中" },
    { "Priority", "优先级" }, { "List", "列表" }, { "Kill", "击杀" },
    { "Spawn", "生成" }, { "Loop", "循环" }, { "Automation", "自动化" },
    { "Quality of Life", "便捷功能" },
    { "Auto Farm", "自动刷取" }, { "Autofarm Settings", "自动刷取设置" },
    { "Item Farming", "刷物品" }, { "Auto Item Farm", "自动刷物品" },
    { "Mob Farming", "刷怪" }, { "Player Farming", "刷玩家" },
    { "Auto Mob Farm", "自动刷怪" }, { "Auto Mob Farm ALL", "自动刷所有怪" },
    { "Auto Farm Player", "自动刷玩家" }, { "Mob Priority List", "怪物优先级列表" },
    { "Target Player", "目标玩家" }, { "Auto Attack", "自动攻击" },
    { "Auto Moves", "自动移动" }, { "Auto Summon", "自动召唤" },
    { "Anti AFK", "防挂机" }, { "Auto Enter", "自动进入" },
    { "Refresh Players", "刷新玩家" }, { "Refresh Mobs", "刷新怪物" },
    { "Refresh Selected Mobs", "刷新已选怪物" },
    { "All", "全部" }, { "Stand", "台" }, { "Toggle All", "全选" },

    -- ===== 外挂领域通用术语 =====
    -- 这一段的定位不是"给某个脚本加词"，而是覆盖整个作弊工具领域的公共词汇。
    -- 词形还原会自动处理复数/进行时（Exploit -> Exploits / Exploiting），
    -- 所以这里只写原形，一条能顶好几种变形。
    -- 作用：这些词机翻必错（Silent Aim→沉默的目标、Dupes→骗子、Exploits→功绩），
    --       必须在词表这一层钉死，否则界面会出很荒唐的译文。

    -- 作弊 / 功能
    { "Exploit", "作弊" }, { "Cheat", "作弊" }, { "Hack", "作弊" },
    { "Script", "脚本" }, { "Executor", "执行器" }, { "Injection", "注入" },
    { "Inject", "注入" }, { "Bypass", "绕过" }, { "Unlock", "解锁" },
    { "Feature", "功能" }, { "Module", "模块" }, { "Utility", "工具" },

    -- 战斗
    { "Aimbot", "自瞄" }, { "Silent Aim", "静默自瞄" }, { "Aim", "瞄准" },
    { "Triggerbot", "扳机自瞄" }, { "Hitbox", "判定框" }, { "Headshot", "爆头" },
    { "Critical", "暴击" }, { "Multiplier", "倍数" }, { "Godmode", "无敌模式" },
    { "God Mode", "无敌模式" }, { "Invincible", "无敌" }, { "Immortal", "不死" },
    { "Weapon", "武器" }, { "Melee", "近战" }, { "Block", "格挡" }, { "Dodge", "闪避" },

    -- 移动
    { "Teleport", "传送" }, { "Fly", "飞行" }, { "Sprint", "冲刺" },
    { "Jump", "跳跃" }, { "Noclip", "穿墙" }, { "Gravity", "重力" },
    { "WalkSpeed", "移动速度" }, { "JumpPower", "跳跃力" },

    -- 视觉 / ESP
    { "ESP", "透视" }, { "Wallhack", "透视" }, { "Chams", "透视染色" },
    { "Highlight", "高亮" }, { "Tracer", "射线" }, { "Skeleton", "骨骼" },
    { "FOV", "视野" }, { "Health Bar", "血条" },

    -- 物品 / 经济 / 刷取
    { "Dupe", "复制" }, { "Duplication", "复制" }, { "Item Drop", "掉落物" },
    { "Drop", "掉落" }, { "Drop Rate", "掉率" }, { "Fishing", "钓鱼" },
    { "Diving", "潜水" }, { "Mining", "挖矿" }, { "Gather", "采集" },
    { "Spoof", "伪装" }, { "Spoofing", "伪装" }, { "Luck", "幸运" },

    -- 系统 / 配置
    { "Toggle", "开关" }, { "Loop", "循环" }, { "Delay", "延迟" },
    { "Preset", "预设" }, { "Webhook", "网络钩子" }, { "Local", "本地" },
    { "Server", "服务器" }, { "Exploits", "作弊" },

    -- UI 结构
    { "Tab", "标签页" }, { "Panel", "面板" }, { "Section", "分区" },
    { "Window", "窗口" }, { "Button", "按钮" }, { "Slider", "滑块" },
    { "Checkbox", "复选框" }, { "Dropdown", "下拉框" }, { "Input", "输入框" },
    { "Visuals", "视觉" }, { "Misc", "杂项" },

    -- 目标
    { "Target NPC", "目标 NPC" }, { "NPC", "NPC" }, { "Ally", "友方" },
    { "Self", "自身" }, { "All Players", "所有玩家" },

    -- 专有名词直通（保证不会因为"没翻"而整句被拒）
    { "Roblox", "Roblox" }, { "Robux", "Robux" }, { "Discord", "Discord" },
}

----------------------------------------------------------------
-- 2. 动态文本规则（数字 / 计时 / 百分比 / 键值对）
----------------------------------------------------------------
local RULES = {
    { "^(%d+) runs?$", "%1 次" },
    { "^(%d+) selected$", "已选 %1 项" },
    { "^(%d+) of (%d+)$", "%1 / %2" },
    { "^(%d+) items?$", "%1 个" },
    { "^(%d+) players?$", "%1 名玩家" },
    { "^(%d+) left$", "剩余 %1" },
    { "^(%d+)%% off$", "%1%% 折扣" },
    -- 说明：简单的「前缀: 值」交给键值对逻辑统一处理（能带上开关值翻译），这里不再写死
    { "^since (.+)$", "自 %1" },
    { "^run (%d+:%d+)$", "用时 %1" },
    { "^(%d+)s/%+(%d+)$", "%1 秒/+%2" },
    { "^(%d+)m$", "%1 分钟" },
    { "^(%d+)h (%d+)m$", "%1 小时 %2 分" },
    { "^auto dodge: (%d+) dodges?, (%d+) hits dodged$", "自动闪避: 闪避 %1 次 / 被击中 %2 次" },
    { "^auto parry: (%d+) parr%a* held, (%d+) hits parried$", "自动格挡: 格挡 %1 次 / 被击中 %2 次" },
    { "^unveils: (%d+) normal, (%d+) super %((%d+) coins each%)$", "揭示: 普通 %1 个 / 超级 %2 个 (每个 %3 金币)" },

    -- 计时 / 计数
    { "^(%d+)h%s*(%d+)m%s*(%d+)s$", "%1 小时 %2 分 %3 秒" },
    { "^(%d+)h%s*(%d+)m$", "%1 小时 %2 分" },
    { "^(%d+)m%s*(%d+)s$", "%1 分 %2 秒" },
    { "^(%d+)h$", "%1 小时" },
    { "^(%d+)s$", "%1 秒" },
    { "^(%d+)d$", "%1 天" },
    { "^(%d+)x$", "%1x" },
    { "^x(%d+)$", "x%1" },
    { "^(%d+)%s*pt$", "%1 点" },
    { "^(%d+)%s*%%$", "%1%%" },
    { "^(%d+)%s*/(%d+)%s*$", "%1 / %2" },
    { "^(%a[%w ]-)%s+owned%s+(%d+)$", "已拥有 %1 %2" },
    { "^(%a[%w ]-)%s+level%s+(%d+)$", "%1 等级 %2" },
}

----------------------------------------------------------------
-- 3. 词表构建
----------------------------------------------------------------
local WORD, EXACT, MULTI = {}, {}, {}

local PHRASE_SRC = {}

local function rebuildDict()
    WORD, EXACT, PHRASE_SRC = {}, {}, {}
    for _, p in ipairs(EXACT_PAIRS) do
        local key = p[1]:lower()
        EXACT[key] = p[2]
        if key:find(" ", 1, true) then
            table.insert(PHRASE_SRC, p)
        else
            WORD[key] = p[2]
        end
    end

    -- 多词短语模式：大小写不敏感、允许 - _ 空格混排
    local function pesc(s)
        return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
    end
    local function ciClass(word)
        local out = {}
        for i = 1, #word do
            local ch = word:sub(i, i)
            if ch:match("%a") then
                out[#out + 1] = "[" .. ch:upper() .. ch:lower() .. "]"
            else
                out[#out + 1] = pesc(ch)
            end
        end
        return table.concat(out)
    end

    local tmp = {}
    for _, p in ipairs(PHRASE_SRC) do
        local key = p[1]:lower()
        local words, wc = {}, 0
        for w in key:gmatch("%S+") do
            words[#words + 1] = ciClass(w)
            wc += 1
        end
        local pat = table.concat(words, "[%s%-_]+")
        if key:sub(1, 1):match("%a") then pat = "%f[%a]" .. pat end
        pat = pat .. "%f[%A]"
        tmp[#tmp + 1] = { pat = pat, cn = p[2], wc = wc }
    end
    table.sort(tmp, function(a, b) return a.wc > b.wc end)
    MULTI = tmp
end

rebuildDict()

-- 翻译结果缓存（词库变更后整体失效）
local CACHE, CACHE_N = {}, 0
local clearCache

function addPairs(list)
    if type(list) ~= "table" then return end
    for _, p in ipairs(list) do
        if type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string" then
            EXACT_PAIRS[#EXACT_PAIRS + 1] = { p[1], p[2] }
        end
    end
    rebuildDict()
    if clearCache then clearCache() end
end

----------------------------------------------------------------
-- 4. 翻译核心
----------------------------------------------------------------
-- 词形还原：Settings -> Setting, Flying -> Fly, Runs -> Run
local function lookupWord(w)
    w = w:lower()
    local v = WORD[w]
    if v then return v end
    local n = #w
    if n >= 3 then
        if n >= 5 and w:sub(n - 2) == "ies" then
            v = WORD[w:sub(1, n - 3) .. "y"]
            if v then return v end
        end
        if n >= 4 and w:sub(n - 1) == "es" then
            v = WORD[w:sub(1, n - 2)]
            if v then return v end
        end
        if w:sub(n) == "s" then
            v = WORD[w:sub(1, n - 1)]
            if v then return v end
        end
    end
    if n >= 5 then
        if w:sub(n - 2) == "ing" then
            local st = w:sub(1, n - 3)
            v = WORD[st] or WORD[st .. "e"]
            if v then return v end
            if #st >= 3 and st:sub(-1) == st:sub(-2, -2) then
                v = WORD[st:sub(1, -2)]
                if v then return v end
            end
        end
        if w:sub(n - 1) == "ed" then
            local st = w:sub(1, n - 2)
            v = WORD[st] or WORD[w:sub(1, n - 1)]
            if v then return v end
            if #st >= 3 and st:sub(-1) == st:sub(-2, -2) then
                v = WORD[st:sub(1, -2)]
                if v then return v end
            end
        end
        if w:sub(n - 2) == "er" then
            v = WORD[w:sub(1, n - 2)] or WORD[w:sub(1, n - 1)]
            if v then return v end
        end
        if w:sub(n - 2) == "est" then
            v = WORD[w:sub(1, n - 3)] or WORD[w:sub(1, n - 2)]
            if v then return v end
        end
        if w:sub(n - 1) == "ly" then
            v = WORD[w:sub(1, n - 2)]
            if v then return v end
        end
    end
    return nil
end

local function countWords(s)
    local n = 0
    for w in s:gmatch("[%a][%w']*") do
        if #w >= 2 then n += 1 end
    end
    return n
end

-- 只在「整串就是这个词」时才翻：出现在句子中间容易翻错（on / to / of / no 等）
local SINGLE_ONLY = {
    ["on"] = true, ["off"] = true, ["to"] = true, ["of"] = true, ["for"] = true,
    ["by"] = true, ["at"] = true, ["in"] = true, ["or"] = true, ["and"] = true,
    ["the"] = true, ["a"] = true, ["an"] = true, ["is"] = true, ["are"] = true,
    ["was"] = true, ["be"] = true, ["as"] = true, ["if"] = true, ["so"] = true,
    ["than"] = true, ["then"] = true, ["it"] = true, ["with"] = true, ["from"] = true,
    ["yes"] = true, ["no"] = true, ["side"] = true, ["once"] = true,
    ["here"] = true, ["there"] = true,
}

-- 允许保留的拉丁词（品牌 / 缩写），不算「漏翻」
local ALLOW_LATIN = {
    roblox = true, robux = true, discord = true, youtube = true, twitch = true,
    github = true, google = true, steam = true, tiktok = true, twitter = true,
    ui = true, ux = true, fps = true, ping = true, hp = true, mp = true, xp = true,
    esp = true, fov = true, afk = true, id = true, api = true, url = true,
    http = true, https = true, dpi = true, gpu = true, cpu = true, npc = true,
    gpb = true, gpbhub = true, ctrl = true, alt = true, shift = true, tab = true,
    lua = true, luau = true, json = true, ok = true, mm2 = true, fps = true,
}

-- 键值对右侧的枚举值（单独出现时才翻，避免句子里误翻 on / off）
local VALUE_MAP = {
    ["on"] = "开", ["off"] = "关", ["yes"] = "是", ["no"] = "否",
    ["true"] = "真", ["false"] = "假", ["enabled"] = "已启用", ["disabled"] = "已禁用",
    ["none"] = "无", ["auto"] = "自动", ["manual"] = "手动", ["default"] = "默认",
    ["random"] = "随机", ["offline"] = "离线", ["online"] = "在线",
    ["normal"] = "普通", ["hard"] = "困难", ["easy"] = "简单",
}

-- 专有名词（玩家名等）：出现时允许保留原文
local PROPER = {}
pcall(function()
    local plrs = game:GetService("Players")
    for _, p in ipairs(plrs:GetPlayers()) do
        if p.Name ~= "" then PROPER[string.lower(p.Name)] = true end
        if p.DisplayName and p.DisplayName ~= "" then PROPER[string.lower(p.DisplayName)] = true end
    end
end)

-- 中文排版：中英/中数之间加空格，标点转全角，中文之间不留空格
local CJK = "[\228-\233][\128-\191][\128-\191]"
local function formatCN(s)
    for _ = 1, 3 do
        s = s:gsub("(" .. CJK .. ")%s+(" .. CJK .. ")", "%1%2")
    end
    s = s:gsub("(" .. CJK .. ")%s*:%s*", "%1：")
    s = s:gsub("(" .. CJK .. ")%s*,%s*", "%1，")
    s = s:gsub("(" .. CJK .. ")%s*;%s*", "%1；")
    s = s:gsub("%s+([：，；！？、])", "%1")
    if s:find(CJK) then
        s = s:gsub("%s*%(([^()]*)%)", "（%1）")
        s = s:gsub("%s+（", "（")
    end
    s = s:gsub("(" .. CJK .. ")([%a%d])", "%1 %2")
    s = s:gsub("([%a%d%%])(" .. CJK .. ")", "%1 %2")
    s = s:gsub("  +", " ")
    s = s:gsub("%s+（", "（")
    return s
end

-- 残留检查：译文里还有没翻掉的普通英文词 -> 视为不合格（宁可整条保留英文）
local function badLeftover(s)
    if not CONFIG.strictNoMixed then return nil end
    for w in s:gmatch("[%a][%w']*") do
        if #w >= 2 then
            local lw = w:lower()
            local allow = ALLOW_LATIN[lw]
            if not allow then
                -- 缩写常带复数后缀：NPCs / ESPs / AFKs / APIs / IDs
                -- 不处理的话，译文里一出现这种词整条就被判成"漏翻"而丢弃
                local stem = lw:gsub("ies$", "y"):gsub("es$", ""):gsub("s$", "")
                allow = ALLOW_LATIN[stem]
                if not allow and lw:sub(-1) == "s" then
                    allow = ALLOW_LATIN[lw:sub(1, -2)]
                end
            end
            if not allow then
                local ok = false
                if w:find("%d") then ok = true                       -- W1 / x1 / 3D
                elseif w:match("^%u%u+$") then ok = true             -- 全大写缩写
                elseif PROPER[lw] then ok = true                     -- 玩家名 / 专有名词
                end
                if not ok then return w end
            end
        end
    end
    return nil
end

local function applyRules(core)
    local low = core:lower()
    for _, r in ipairs(RULES) do
        local ok, res, n = pcall(string.gsub, low, r[1], r[2])
        if ok and n and n > 0 then return res end
    end
    return nil
end

local function phrasePass(s)
    local changed = false
    for i = 1, #MULTI do
        local e = MULTI[i]
        local new, n = s:gsub(e.pat, function() return e.cn end)
        if n and n > 0 then
            s = new
            changed = true
        end
    end
    return s, changed
end

local function wordPass(s)
    local changed = false
    -- 连字符复合词先整体查：Anti-Cheat / Auto-Farm / Walk-Speed
    s = s:gsub("([%a][%w']*%-[%a][%w'%-]*)", function(w)
        local cn = WORD[w:lower()] or lookupWord(w)
        if cn then changed = true; return cn end
        return w
    end)
    local out = s:gsub("([%a][%w']*)", function(w)
        local lw = w:lower()
        if SINGLE_ONLY[lw] and #w <= 4 then return w end
        local cn = lookupWord(w)
        if cn then changed = true; return cn end
        return w
    end)
    return out, changed
end

-- 句式模板：先整句改写成中文语序，再翻其中残留的英文词
local ON_EVENT = {
    ["disconnect"] = "断线", ["death"] = "死亡", ["spawn"] = "出生",
    ["respawn"] = "复活", ["join"] = "加入", ["low health"] = "低血量",
    ["low hp"] = "低血量", ["kill"] = "击杀", ["hit"] = "受击",
    ["full inventory"] = "背包满", ["full"] = "满",
}

local SURROUND = {
    -- 回调参数：(捕获1, 捕获2, 翻译函数)；翻译函数翻不出来就返回 nil，模板自动放弃
    { "^no%s+(.+)%s+selected$", function(a, _, tr) local x = tr(a); return x and ("未选中" .. x) end },
    { "^no%s+(.+)%s+chosen$", function(a, _, tr) local x = tr(a); return x and ("未选中" .. x) end },
    { "^no%s+(.+)%s+found$", function(a, _, tr) local x = tr(a); return x and ("未找到" .. x) end },
    { "^no%s+(.+)%s+available$", function(a, _, tr) local x = tr(a); return x and ("无可用" .. x) end },
    { "^no%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("无" .. x) end },
    { "^(.+)%s+now$", function(a, _, tr) local x = tr(a); return x and ("立即" .. x) end },
    { "^(.+)%s+in%s+use$", function(a, _, tr) local x = tr(a); return x and (x .. "使用中") end },
    { "^(.+)%s+on%s+(.-)$", function(a, b, tr)
        local ev = b and ON_EVENT[b:lower()]
        if not ev then return nil end
        local x = tr(a)
        return x and (ev .. "时" .. x)
    end },
    { "^enable%s+(.+)%s+for%s+(.+)$", function(a, b, tr)
        local x, y = tr(a), tr(b)
        return (x and y) and ("为" .. y .. "启用" .. x) or nil
    end },
    { "^teleport%s+to%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("传送到" .. x) end },
    { "^reset%s+to%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("重置为" .. x) end },
    { "^create%s+new%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("新建" .. x) end },
    { "^import%s+from%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("从" .. x .. "导入") end },
    { "^export%s+to%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("导出到" .. x) end },
    { "^show%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("显示" .. x) end },
    { "^hide%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("隐藏" .. x) end },
    { "^use%s+(.+)$", function(a, _, tr) local x = tr(a); return x and ("使用" .. x) end },
    { "^(.+)%s+when%s+(.+)$", function(a, b, tr)
        local x, y = tr(a), tr(b)
        return (x and y) and (y .. "时" .. x) or nil
    end },
    { "^(.+)%s+only$", function(a, _, tr) local x = tr(a); return x and ("仅" .. x) end },
}

local translateCore

local function surroundPass(core)
    local low = core:lower()
    for _, t in ipairs(SURROUND) do
        local caps = { low:match(t[1]) }
        if caps[1] then
            local ok2, res = pcall(t[2], caps[1], caps[2], translateCore)
            if ok2 and type(res) == "string" then return res end
        end
    end
    return nil
end

translateCore = function(core)
    if core == "" then return nil end

    -- 1) 整串精确
    local low = core:lower()
    local hit = EXACT[low]
    if not hit then hit = EXACT[low:gsub("[-_]+", " "):gsub("%s+", " ")] end
    if not hit then hit = EXACT[low:gsub(":%s*$", "")] end
    if hit then return formatCN(hit) end

    -- 2) 竖线分隔的复合行
    if core:find("|", 1, true) then
        local parts, any = {}, false
        for part in (core .. "|"):gmatch("([^|]*)|") do
            local seg = part:match("^%s*(.-)%s*$")
            local r = translateCore(seg)
            if r then any = true; parts[#parts + 1] = r else parts[#parts + 1] = part end
        end
        if not any then return nil end
        local joined = table.concat(parts, " | ")
        if badLeftover(joined) then return nil end
        return formatCN(joined)
    end

    -- 3) 动态规则 / 句式模板
    local base, seeded = applyRules(core), true
    if not base then
        base = surroundPass(core)
        if not base then seeded = false end
    end

    -- 4) 键值对：Settings: xxx / Equipped: Iron Pole / Reconnect: Off
    if not base then
        local k, v = core:match("^(.-):%s*(.-)$")
        if k and v and k ~= "" and v ~= "" and not v:find(":", 1, true) then
            local kk = translateCore(k)
            if kk then
                local vv = VALUE_MAP[v:lower()] or v
                if not VALUE_MAP[v:lower()] and v:find("[%a]") then vv = translateCore(v) or v end
                local joined = kk .. "：" .. vv
                if not badLeftover(joined) then return formatCN(joined) end
            end
            return nil
        end
        base = core
    end

    -- 5) 短语 + 单词
    local step, phChanged = phrasePass(base)
    local out, wChanged = wordPass(step)
    if not (seeded or phChanged or wChanged) then return nil end
    if not out:find("[\228-\233]") then return nil end
    if badLeftover(out) then return nil end
    return formatCN(out)
end

local function translatePlain(seg)
    local lead = seg:match("^(%s*)") or ""
    local trail = seg:match("(%s*)$") or ""
    local core = seg:match("^%s*(.-)%s*$")
    if core == "" then return seg, false end
    local out = translateCore(core)
    if not out then return seg, false end
    return lead .. out .. trail, true
end

-- 富文本：<font ...>…</font> 标签保留，只翻标签之间的文字
local function translateSegment(seg)
    if not seg:find("<", 1, true) then
        return translatePlain(seg)
    end
    local parts, changed = {}, false
    local i = 1
    while i <= #seg do
        local lt = seg:find("<", i, true)
        if not lt then
            local r, ch = translatePlain(seg:sub(i))
            parts[#parts + 1] = r
            changed = changed or ch
            break
        end
        if lt > i then
            local r, ch = translatePlain(seg:sub(i, lt - 1))
            parts[#parts + 1] = r
            changed = changed or ch
        end
        local gt = seg:find(">", lt, true)
        if not gt then
            parts[#parts + 1] = seg:sub(lt)
            break
        end
        parts[#parts + 1] = seg:sub(lt, gt)
        i = gt + 1
    end
    return table.concat(parts), changed
end

-- 结果缓存：菜单里同一串文字会反复出现
clearCache = function() CACHE, CACHE_N = {}, 0 end

----------------------------------------------------------------
-- 4.5 自动翻译引擎
----------------------------------------------------------------
-- 词表翻不出来的文本，先入队，再由 worker 协程调用在线翻译接口，
-- 结果写进 AUTO.cache 并触发重扫，界面上就会即时变成中文。
-- 设计要点：
--   · 词表优先（本地、零延迟、稳定），只在词表没覆盖时才走网络
--   · 后端自动探测：google -> mymemory -> youdao，哪个通用哪个
--   · 玩家名 / 标识符 / 长句 / 含中文的串 一律不入队，避免翻出一堆乱码
--   · 全程 pcall 兜底，网络挂了就静默退回纯词表模式，不影响原功能
local AUTO = {
    cache     = {},   -- [英文原文] = 中文
    pending   = {},   -- [英文原文] = true 已入队
    queue     = {},   -- 待翻队列
    provider  = nil,  -- 探测出的可用后端
    enabled   = false,
    started   = false,
    okCount   = 0,
    failCount = 0,
    skipNames = {},
    onTranslated = nil,
}

-- JSON 字符串反转义（\uXXXX 中文 / \" / \n / \\）
local function jsonUnescape(s)
    if not s:find("\\", 1, true) then return s end
    s = s:gsub("\\u(%x%x%x%x)", function(h)
        local cp = tonumber(h, 16)
        if cp < 0x80 then return string.char(cp) end
        if cp < 0x800 then
            return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
        end
        return string.char(
            0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor((cp % 0x1000) / 0x40),
            0x80 + cp % 0x40)
    end)
    s = s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\/", "/")
    return s
end

local function urlEncode(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function httpGet(url)
    local fn = ENV.request or ENV.http_request
    if type(fn) ~= "function" and type(ENV.http) == "table" then
        fn = ENV.http.request
    end
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, {
        Url = url,
        Method = "GET",
        Headers = { ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" },
        Timeout = CONFIG.apiTimeoutMs,
    })
    if not ok or type(res) ~= "table" then return nil end
    local code = tonumber(res.StatusCode or res.status)
    if code and code ~= 200 then return nil end
    local body = res.Body or res.body
    if type(body) ~= "string" or body == "" then return nil end
    return body
end

local PROVIDERS = {
    -- 响应最短最干净：[[["竞赛模式","Race Mode",...],...],null,"en",...]
    google = function(text)
        local body = httpGet("https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q=" .. urlEncode(text))
        if not body then return nil end
        local segs = {}
        for tgt, src in body:gmatch('%["([^"]*)"%s*,%s*"([^"]*)"') do
            -- 结尾会跟一个 ["<32位hash>","en_zh_xxx.md"] 的元数据对，排除掉
            if not tgt:match("^%x+$") and src ~= "" then
                segs[#segs + 1] = jsonUnescape(tgt)
            end
        end
        if #segs == 0 then return nil end
        return table.concat(segs)
    end,

    -- 免 key，返回 {"responseData":{"translatedText":"\u6bd4\u8d5b\u6a21\u5f0f"}}
    mymemory = function(text)
        local body = httpGet("https://api.mymemory.translated.net/get?q=" .. urlEncode(text) .. "&langpair=en%7Czh-CN")
        if not body then return nil end
        local tgt = body:match('"translatedText"%s*:%s*"([^"]*)"')
        if not tgt or tgt == "" then return nil end
        return jsonUnescape(tgt)
    end,

    -- 有道词典接口，中文质量好但带 <b> 标签要洗掉
    youdao = function(text)
        local body = httpGet("https://dict.youdao.com/jsonapi?q=" .. urlEncode(text))
        if not body then return nil end
        local tgt = body:match('"summary"%s*:%s*%{"line"%s*:%s*%[%s*"([^"]*)"')
        if not tgt then
            tgt = body:match('"trs"%s*:%s*%[%s*%{"tr"%s*:%s*%[%s*%{"l"%s*:%s*%{"i"%s*:%s*%[%s*"([^"]*)"')
        end
        if not tgt then return nil end
        tgt = jsonUnescape(tgt):gsub("<b>", ""):gsub("</b>", ""):gsub("<[^>]->", "")
        return tgt
    end,
}

-- 批量翻译：google 端点支持把多条用换行拼起来一次翻完（多 q 参数无效，实测确认）。
-- 返回按输入顺序对齐的译文数组；条数对不上就返回 nil，由调用方退回逐条翻译。
-- 这是吞吐的关键：原来一条一请求，队列一堵就是几分钟；批量后一批十几条。
local function googleBatch(texts)
    local n = #texts
    if n == 0 then return nil end
    if n == 1 then
        local one = PROVIDERS.google(texts[1])
        return one and { one } or nil
    end

    local clean = {}
    for i = 1, n do
        -- 换行会破坏批量对齐，先压成空格
        clean[i] = (tostring(texts[i]):gsub("[\r\n]+", " "))
    end
    local body = httpGet("https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q="
        .. urlEncode(table.concat(clean, "\n")))
    if not body then return nil end

    local segs = {}
    for tgt in body:gmatch('%["([^"]*)"%s*,%s*"') do
        if not tgt:match("^%x+$") then
            local s = jsonUnescape(tgt):gsub("%s+$", "")
            if s ~= "" then segs[#segs + 1] = s end
        end
    end
    -- 服务端会把长句拆成多段，导致条数错位；这种情况放弃批量，退回逐条更稳
    if #segs ~= n then return nil end
    return segs
end

-- 判断一段文本值不值得送去机翻
local function worthTranslate(s)
    if type(s) ~= "string" then return false end
    local n = #s
    if n < 2 or n > CONFIG.maxTextLen then return false end
    if s:find("[\228-\233]") then return false end            -- 已含中文
    if s:find("http", 1, true) or s:find("www.", 1, true) then return false end
    local letters = 0
    for _ in s:gmatch("%a") do letters += 1 end
    if letters < 2 then return false end                      -- 数字/符号为主
    -- 标识符样式：无空格且含 2 个以上大写（RiverbendCanyon / BackseatRally）→ 专有名词，别翻
    local _, upper = s:gsub("[^%u]", "")
    if not s:find("%s") and upper >= 2 then return false end
    if CONFIG.skipPlayerNames and AUTO.skipNames[s] then return false end
    return true
end

function AUTO.enqueue(s)
    if not AUTO.enabled then return false end
    if AUTO.cache[s] or AUTO.pending[s] then return false end
    if #AUTO.queue >= CONFIG.maxQueue then return false end
    if not worthTranslate(s) then return false end
    AUTO.pending[s] = true
    AUTO.queue[#AUTO.queue + 1] = s
    return true
end

local function pickProvider()
    if AUTO.provider then return AUTO.provider end
    local want = CONFIG.apiProvider
    if want and want ~= "auto" and PROVIDERS[want] then
        AUTO.provider = want
        return want
    end
    for _, name in ipairs({ "google", "mymemory", "youdao" }) do
        local ok, r = pcall(PROVIDERS[name], "Drive")
        if ok and type(r) == "string" and r ~= "" and r:find("[\228-\233]") then
            AUTO.provider = name
            return name
        end
    end
    return nil
end

local function workerLoop()
    local provider = pickProvider()
    if not provider then
        AUTO.enabled = false
        if CONFIG.verbose then
            warn("[UIT-CN] 自动翻译不可用（翻译接口全部请求失败），已退回纯词表模式")
        end
        return
    end
    if CONFIG.verbose then
        print("[UIT-CN] 自动翻译已启用，后端: " .. provider)
    end

    local function applyOne(src, tgt)
        if tgt and tgt ~= "" and tgt:lower() ~= src:lower() then
            AUTO.cache[src] = tgt
            CACHE[src] = nil          -- 清掉「翻不出」的负缓存，让 translate 重算
            AUTO.okCount += 1
        else
            AUTO.failCount += 1
        end
        AUTO.pending[src] = nil
    end

    while AUTO.enabled do
        local n = #AUTO.queue
        if n == 0 then
            task.wait(0.4)
        else
            local batch = {}
            for i = 1, math.min(CONFIG.apiBatch, n) do
                batch[i] = table.remove(AUTO.queue, 1)
            end

            -- 首选批量：一次请求翻一整批，吞吐提升一个数量级，队列不会再堵
            local tgtList = nil
            if provider == "google" then
                local ok, r = pcall(googleBatch, batch)
                if ok and type(r) == "table" then tgtList = r end
            end

            if tgtList then
                for i, src in ipairs(batch) do
                    applyOne(src, tgtList[i])
                end
            else
                -- 批量失败（条数错位 / 网络抖动）→ 退回逐条，保证不丢
                local done, total = 0, #batch
                for _, src in ipairs(batch) do
                    task.spawn(function()
                        local tgt = nil
                        for _ = 0, CONFIG.apiRetries do
                            local ok, r = pcall(PROVIDERS[provider], src)
                            if ok and type(r) == "string" and r ~= "" then
                                tgt = r
                                break
                            end
                            task.wait(0.3)
                        end
                        applyOne(src, tgt)
                        done += 1
                    end)
                end
                local t0 = os.clock()
                while done < total and (os.clock() - t0) < 20 do
                    task.wait(0.05)
                end
            end

            if AUTO.onTranslated then pcall(AUTO.onTranslated) end
            task.wait(CONFIG.apiInterval)
        end
    end
end

function AUTO.start()
    if AUTO.started then return end
    AUTO.started = true
    AUTO.enabled = (CONFIG.autoTranslate == true)
    if not AUTO.enabled then return end
    -- 收集玩家名，这些人名不该被翻
    pcall(function()
        for _, pl in ipairs(PlayersSvc:GetPlayers()) do
            AUTO.skipNames[pl.Name] = true
            AUTO.skipNames[pl.DisplayName] = true
        end
        PlayersSvc.PlayerAdded:Connect(function(pl)
            pcall(function()
                AUTO.skipNames[pl.Name] = true
                AUTO.skipNames[pl.DisplayName] = true
            end)
        end)
    end)
    task.spawn(workerLoop)
end

function AUTO.stats()
    local cached = 0
    for _ in pairs(AUTO.cache) do cached += 1 end
    return {
        provider = AUTO.provider or "none",
        enabled  = AUTO.enabled,
        cached   = cached,
        queue    = #AUTO.queue,
        ok       = AUTO.okCount,
        fail     = AUTO.failCount,
    }
end

local function translate(s)
    if type(s) ~= "string" or s == "" then return nil end
    if not s:find("[%a]") then return nil end            -- 纯数字/符号
    if s:find("[\228-\233]") then return nil end          -- 已含中文
    if s:find("http", 1, true) or s:find("www.", 1, true) then return nil end

    -- 1) 词表正缓存：命中就返回。词表永远是第一优先级，
    --    否则机翻的烂译法（Auto→汽车）一旦进缓存，加词条也盖不住。
    local cached = CACHE[s]
    if cached then return cached end

    -- 2) 词表翻译。cached == false 表示"算过但翻不出"，不用重复计算
    local res = nil
    if cached == nil then
        local out, changed = {}, false
        for line in (s .. "\n"):gmatch("([^\n]*)\n") do
            local r, ch = translateSegment(line)
            out[#out + 1] = r
            changed = changed or ch
        end
        if changed then res = table.concat(out, "\n") end
        if CACHE_N > 4000 then clearCache() end
        CACHE[s] = res or false
        CACHE_N += 1
        if res then return res end
    end

    -- 3) 词表翻不出 -> 用机翻结果兜底
    local ai = AUTO.cache[s]
    if ai then return ai end

    -- 4) 两边都没有 -> 排队（enqueue 内部幂等，重复调用不会重复入队）
    if AUTO.enabled then AUTO.enqueue(s) end
    return nil
end

----------------------------------------------------------------
-- 5. 应用到实例
----------------------------------------------------------------
-- 用 ClassName 判定（移动端受限容器里 IsA 可能抛错，这里全程 pcall 兜住）
local TEXT_CLASS = { TextLabel = true, TextButton = true, TextBox = true }

local function isText(o)
    local ok, cn = pcall(function() return o.ClassName end)
    return (ok and TEXT_CLASS[cn]) or false
end

local state = {
    enabled     = true,
    running     = false,
    originals   = setmetatable({}, { __mode = "k" }),
    phOriginals = setmetatable({}, { __mode = "k" }),
    hooked      = setmetatable({}, { __mode = "k" }),
    confirmed   = setmetatable({}, { __mode = "k" }),  -- 已确认属于目标菜单的文本元素
    busy        = setmetatable({}, { __mode = "k" }),
    conns       = {},
    count       = 0,
    guis        = 0,
    usePlayerGui = false,   -- 是否已进入 PlayerGui 兜底模式（重新启用时要沿用）
}

local translateObj

local function watchObj(o)
    if state.hooked[o] then return end
    state.hooked[o] = true
    local ok, c = pcall(function()
        return o:GetPropertyChangedSignal("Text"):Connect(function()
            if state.enabled and state.running and not state.busy[o] then
                task.defer(translateObj, o)
            end
        end)
    end)
    if ok and c then table.insert(state.conns, c) else state.hooked[o] = nil end
end

-- 真正的写属性逻辑（外层 pcall 包裹，任何属性被锁都不影响其它元素）
local function applyTo(o)
    if not state.enabled or not isText(o) then return 0 end
    if state.busy[o] then return 0 end
    if o:GetAttribute("UIT_SELF") then return 0 end

    local changed = 0

    local raw = o.Text
    if type(raw) == "string" and raw ~= "" then
        local new = translate(raw)
        if new and new ~= raw then
            state.originals[o] = raw
            state.busy[o] = true
            local ok = pcall(function() o.Text = new end)
            state.busy[o] = nil
            if ok then
                changed = 1
                state.count += 1
            end
        end
    end

    if o.ClassName == "TextBox" then
        local ph = o.PlaceholderText
        if type(ph) == "string" and ph ~= "" and not state.phOriginals[o] then
            local newph = translate(ph)
            if newph and newph ~= ph then
                state.phOriginals[o] = ph
                pcall(function() o.PlaceholderText = newph end)
            end
        end
    end
    return changed
end

translateObj = function(o)
    local ok, n = pcall(applyTo, o)
    if ok then return n or 0 end
    return 0
end

local function restoreAll()
    local n = 0
    for inst, txt in pairs(state.originals) do
        if isInst(inst) and inst.Parent then
            state.busy[inst] = true
            if pcall(function() inst.Text = txt end) then n += 1 end
            state.busy[inst] = nil
        end
    end
    for inst, txt in pairs(state.phOriginals) do
        if isInst(inst) and inst.Parent then
            pcall(function() inst.PlaceholderText = txt end)
        end
    end
    state.count = 0
    return n
end

----------------------------------------------------------------
-- 6. 自动识别脚本菜单
----------------------------------------------------------------
-- Roblox 自带界面：一律不碰
local BUILTIN = {
    robloxgui = true, chat = true, bubblechat = true, experiencechat = true,
    playerlist = true, backpack = true, topbarapp = true, shortcutbar = true,
    robloxpromptgui = true, teleportgui = true, teleporteffectgui = true,
    robloxnetworkpauseneonnotification = true, screenshotsCarousel = true,
    capturemanager = true, captureoverlay = true, systemscrim = true,
    toastnotification = true, settingsclippingshield = true,
    headsetdisconnecteddialog = true, ingamefullscreenTitlebarScreen = true,
    foundationoverlay = true, purchasespromptapp = true, purchasepromptapp = true,
    bulkpurchaseapp = true, inexperiencetransferapp = true, cancelsubscriptionapp = true,
    commercepurchaseapp = true, universalsharesheetscreengui = true,
    inexperiencentitiespromptapp = true, inexpperiencedetailspromptapp = true,
    inexperienciedetailspromptapp = true, avatareditorpromptsapp = true,
    gameinvite = true, socialcontexttoast = true, publishassetprompt = true,
    momentscreationflow = true, selfieqrroot = true, selfieconsentroot = true,
    foundationcursorcontainer = true, cursorcontainer = true,
    dropdownfullscreenframe = true, notificationframe = true, popupframe = true,
    errorprompt = true, controlframe = true, promptdialog = true,
    vehiclehudframe = true, avatarcontextmenu = true, immersivebrandedads = true,
    rewardedvideoadplayer = true, adguiinteractivitycontrols = true,
    appchat = true, inexperienciatrack = true, engagementtouchhandler = true,
}

-- 菜单特征词：用来判断一个 GUI 是不是脚本菜单
-- 注意：这份表是「打分用」的，词越贴近真实菜单越准。
--       早期版本只有 FPS 外挂词（aimbot/esp/noclip/fly），导致赛车、模拟、经营、
--       抽卡类脚本一个词都命中不到，于是整块被判定为「不是菜单」而跳过。
--       下面按领域分组补齐，仍然只用有辨识度的词，不放 on/off/yes/no 这类超短词。
local MARKERS = {
    -- 判定用打分表：只要命中 1 个就算菜单（CONFIG.minMenuScore = 1）。
    -- 分组覆盖：面板结构 / 外挂通用 / 赛车驾驶 / 经济进度 / 玩法商店 / 设置控件。
    toggle=1, enabled=1, disabled=1, auto=1, settings=1, config=1, option=1, options=1,
    menu=1, panel=1, window=1, tab=1, button=1, label=1, title=1, header=1, status=1,
    system=1, check=1, mode=1, selected=1, current=1, map=1, stage=1,
    start=1, stop=1, pause=1, paused=1, resume=1, restart=1, exit=1, close=1, open=1,
    enable=1, disable=1, apply=1, save=1, load=1, reset=1, default=1, custom=1,
    esp=1, aimbot=1, aim=1, silent=1, fly=1, noclip=1, godmode=1, speed=1, keybind=1,
    hotkey=1, teleport=1, farm=1, fps=1, ping=1, hub=1, script=1, feature=1, features=1,
    player=1, players=1, team=1, enemy=1, target=1, damage=1, health=1, weapon=1,
    race=1, racing=1, rally=1, car=1, cars=1, vehicle=1, drive=1, driver=1, drift=1,
    lap=1, track=1, gear=1, engine=1, nitro=1, boost=1, checkpoint=1, finish=1, garage=1,
    credit=1, credits=1, earning=1, earnings=1, coin=1, coins=1, cash=1, money=1,
    gem=1, gems=1, token=1, reward=1, rewards=1, balance=1, price=1, cost=1, total=1,
    level=1, lvl=1, rank=1, exp=1, xp=1, progress=1, unlock=1, claim=1, collect=1, streak=1,
    shop=1, store=1, market=1, inventory=1, backpack=1, item=1, items=1, buy=1, sell=1,
    purchase=1, crate=1, chest=1, upgrade=1, quest=1, mission=1, challenge=1, loot=1,
    amount=1, value=1, interval=1, delay=1, distance=1, radius=1, range=1, buffer=1,
    slider=1, checkbox=1, dropdown=1, input=1, threshold=1, smoothing=1, prediction=1,
}

local guiCache = setmetatable({}, { __mode = "k" })  -- [gui] = { ok = bool, t = clock }
local targetCount = 0

local function countTargets()
    local n = 0
    for _, e in pairs(guiCache) do if e.ok then n += 1 end end
    return n
end

-- 一次遍历同时取「文本量」和「菜单特征词命中数」（原来遍历两遍，手机上白白多一倍开销）
local function analyze(gui)
    local count, score = 0, 0
    local seen = {}
    pcall(function()
        for _, d in ipairs(gui:GetDescendants()) do
            if isText(d) then
                count += 1
                local t = d.Text
                if type(t) == "string" then
                    for w in t:lower():gmatch("[%a]+") do
                        if MARKERS[w] and not seen[w] then
                            seen[w] = true
                            score += 1
                        end
                    end
                end
            end
        end
    end)
    return count, score
end

local function nameExcluded(name)
    local n = tostring(name):lower()
    if BUILTIN[n] then return true end
    for _, pat in ipairs(CONFIG.extraExclude) do
        if n:find(pat:lower(), 1, true) then return true end
    end
    return false
end

local function nameIncluded(name)
    local n = tostring(name):lower()
    for _, pat in ipairs(CONFIG.includeNames) do
        if n:find(pat:lower(), 1, true) then return true end
    end
    for _, pat in ipairs(CONFIG.forceInclude or {}) do
        if n:find(pat:lower(), 1, true) then return true end
    end
    return false
end

-- 判断某个 GUI（容器下的一级子项）是否为目标菜单
-- strict = true：必须是「文本量够 + 命中菜单特征词」双条件（PlayerGui 兜底时用，防误翻游戏 HUD）
local function isTarget(gui, strict)
    if not isInst(gui) then return false end
    if not safeGet(function() return gui.Parent ~= nil end, false) then return false end

    local cached = guiCache[gui]
    if cached and (os.clock() - cached.t) < CONFIG.cacheSeconds then
        return cached.ok
    end

    local ok, res = pcall(function()
        local name = gui.Name
        if nameExcluded(name) then return false end
        if gui:GetAttribute("UIT_SELF") then return false end

        -- 强制纳入（includeNames / forceInclude）：不再参与打分，直接翻
        if nameIncluded(name) then return true end

        local tc, sc = analyze(gui)
        if tc < CONFIG.minTextsForMenu then return false end
        if strict then return sc >= CONFIG.minMenuScore end
        if tc >= CONFIG.bigTextsForMenu then return true end
        return sc >= CONFIG.minMenuScore
    end)
    res = (ok and res) == true

    if res and not (cached and cached.ok) then
        targetCount += 1
        state.guis = targetCount
    end
    guiCache[gui] = { ok = res, t = os.clock() }
    return res
end

-- 容器列表：探测到哪个用哪个，参数 includePlayerGui 强制把 PlayerGui 也纳入
local function containerList(includePlayerGui)
    local list, seen = {}, {}
    local function add(v)
        if isInst(v) and not seen[v] then
            seen[v] = true
            list[#list + 1] = v
        end
    end
    add(tryHiddenRoot())
    add(safeGet(function() return game:GetService("CoreGui") end))
    if includePlayerGui or CONFIG.translatePlayerGui then
        add(getPlayerGui())
    end
    return list
end

-- 沿祖先链找最近的「菜单级」GUI
-- 只认 ScreenGui（脚本菜单基本都是 ScreenGui），Name 显式指定的容器才放宽；
-- BillboardGui / SurfaceGui 属于游戏内 3D UI，一律不碰
local function targetAncestor(o, strict)
    local ok, res = pcall(function()
        local p = o.Parent
        local depth = 0
        while p and depth < 40 do
            local c = guiCache[p]
            if c and c.ok then return p end
            local cn = p.ClassName
            if cn == "ScreenGui" then
                if isTarget(p, strict) then return p end
            elseif cn == "BillboardGui" or cn == "SurfaceGui" then
                -- 3D 世界标签默认不碰（满地图广告牌会被翻乱）
                -- CONFIG.includeBillboard = true 时放开：文本量小，不参与打分，有字就认
                if CONFIG.includeBillboard then
                    if nameIncluded(p.Name) then
                        guiCache[p] = { ok = true, t = os.clock() }
                        targetCount += 1
                        state.guis = targetCount
                        return p
                    end
                    local tc = select(1, analyze(p))
                    if tc >= 1 then
                        guiCache[p] = { ok = true, t = os.clock() }
                        targetCount += 1
                        state.guis = targetCount
                        return p
                    end
                end
                return nil
            elseif nameIncluded(p.Name) then
                guiCache[p] = { ok = true, t = os.clock() }
                targetCount += 1
                state.guis = targetCount
                return p
            end
            p = p.Parent
            depth += 1
        end
        return nil
    end)
    return (ok and res) or nil
end

-- 分帧扫描：每处理一小批就把控制权还给引擎，手机上不卡、也不会被判定脚本超时
local function sweepContainer(c, strict)
    if not isInst(c) then return 0 end
    local ok, desc = pcall(function() return c:GetDescendants() end)
    if not ok or type(desc) ~= "table" then return 0 end

    local n, t0 = 0, os.clock()
    for i = 1, #desc do
        if (os.clock() - t0) >= CONFIG.frameBudget then
            task.wait()
            t0 = os.clock()
            if not state.running then return n end
        end

        local d = desc[i]
        if state.confirmed[d] then
            n += translateObj(d)
        elseif isText(d) then
            local tgt = targetAncestor(d, strict)
            if tgt then
                state.confirmed[d] = true
                watchObj(d)
                n += translateObj(d)
            end
        end
    end
    return n
end

local function sweepAll(includePlayerGui, strict)
    local total = 0
    local list = containerList(includePlayerGui)
    local pg = nil
    if includePlayerGui or CONFIG.translatePlayerGui then pg = getPlayerGui() end
    for _, c in ipairs(list) do
        -- 只有「兜底扫 PlayerGui」时才强制严格判定；
        -- 用户主动把 translatePlayerGui 打开 = 想连游戏 HUD 一起翻，就不加严格限制
        local s = (strict == true) or ((pg ~= nil and c == pg) and not CONFIG.translatePlayerGui)
        local ok, r = pcall(sweepContainer, c, s)
        if ok then total += r end
    end
    return total
end

----------------------------------------------------------------
-- 7. 「中 / EN」浮动按钮（触屏拖拽版）
----------------------------------------------------------------
local toggleGui, toggleBtn = nil, nil
local toggleTries = 0
local setEnabled

local function refreshToggleText()
    if toggleBtn then
        pcall(function() toggleBtn.Text = state.enabled and "中" or "EN" end)
    end
end

local function buildToggle()
    if not CONFIG.showToggle or toggleGui then return end
    if toggleTries >= 8 then return end          -- 探测失败不要无限重试

    local parent = resolveGuiParent()
    if not parent then
        toggleTries += 1
        task.delay(2, function()
            if state.running then buildToggle() end
        end)
        return
    end
    toggleTries += 1

    local ok, err = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "UIT_CN_Toggle"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 999999
        gui:SetAttribute("UIT_SELF", true)

        local btn = Instance.new("TextButton")
        btn.Name = "Toggle"
        btn:SetAttribute("UIT_SELF", true)

        -- 触屏手指需要更大的点击区域
        local w, h = 44, 28
        if CONFIG.toggleSize then
            w = CONFIG.toggleSize[1] or w
            h = CONFIG.toggleSize[2] or h
        elseif UserInput and UserInput.TouchEnabled then
            w, h = 56, 36
        end

        btn.Size = UDim2.fromOffset(w, h)
        btn.Position = UDim2.new(1, -(w + 14), 0, 96)
        btn.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
        btn.BackgroundTransparency = 0.05
        btn.TextColor3 = Color3.fromRGB(240, 240, 240)
        btn.TextSize = 15
        btn.Text = state.enabled and "中" or "EN"
        btn.AutoButtonColor = true
        btn.Active = true
        pcall(function() btn.Font = Enum.Font.GothamBold end)
        btn.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = btn

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(72, 72, 80)
        stroke.Thickness = 1
        stroke.Parent = btn

        -- ---- 触摸 / 鼠标拖拽（Draggable 已废弃，安卓上根本拖不动，改手动实现）----
        local dragging, dragStart, startPos, moved = false, nil, nil, false

        btn.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                dragging, moved = true, false
                dragStart = input.Position
                startPos = btn.Position
            end
        end)

        if UserInput then
            table.insert(state.conns, UserInput.InputChanged:Connect(function(input)
                if not dragging or not dragStart then return end
                local t = input.UserInputType
                if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
                local delta = input.Position - dragStart
                if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then moved = true end
                btn.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end))

            table.insert(state.conns, UserInput.InputEnded:Connect(function(input)
                local t = input.UserInputType
                if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                    if dragging then
                        dragging = false
                        -- 拖完立刻抬手会误触点击，延迟清标志
                        if moved then task.delay(0.25, function() moved = false end) end
                    end
                end
            end))
        end

        btn.MouseButton1Click:Connect(function()
            if moved then return end
            setEnabled(not state.enabled)
        end)

        gui.Parent = parent
        toggleGui, toggleBtn = gui, btn
    end)

    if not ok then
        warn("[UIT-CN] 按钮创建失败: " .. tostring(err))
    end
end

setEnabled = function(on)
    state.enabled = on
    refreshToggleText()
    if on then
        if state.usePlayerGui then sweepAll(true, true) else sweepAll(false) end
    else
        restoreAll()
    end
end

----------------------------------------------------------------
-- 8. 启动 / 停止 / 对外接口
----------------------------------------------------------------
-- 新建元素队列：DescendantAdded 在界面构建时会疯狂触发，
-- 手机上必须合并成批处理，否则一开菜单就掉帧
local newQueue, flushQueued = {}, false

local function flushNewQueue()
    flushQueued = false
    if not state.running or not state.enabled then
        newQueue = {}
        return
    end
    local batch = newQueue
    newQueue = {}
    local t0 = os.clock()
    for i = 1, #batch do
        if (os.clock() - t0) >= CONFIG.frameBudget then
            task.wait()
            t0 = os.clock()
            if not state.running then return end
        end
        local d, strict = batch[i][1], batch[i][2]
        if isInst(d) and isText(d) then
            if state.confirmed[d] then
                translateObj(d)
            else
                local tgt = targetAncestor(d, strict)
                if tgt then
                    state.confirmed[d] = true
                    watchObj(d)
                    translateObj(d)
                end
            end
        end
    end
end

local function scheduleFlush()
    if flushQueued then return end
    flushQueued = true
    task.delay(0.15, flushNewQueue)
end

local function hookNewUI(container, strict)
    if not isInst(container) then return end
    local ok, conn = pcall(function()
        return container.DescendantAdded:Connect(function(d)
            if not state.running or not state.enabled then return end
            if #newQueue >= 3000 then return end          -- 极端情况直接丢弃，交给兜底重扫
            if not isText(d) then return end
            newQueue[#newQueue + 1] = { d, strict }
            scheduleFlush()
        end)
    end)
    if ok and conn then table.insert(state.conns, conn) end
end

local function start()
    buildToggle()

    -- 0) 必须先启动自动翻译，再扫描。
    --    反过来的话，第一轮扫描时 AUTO 还没就绪，识别不出的文本会被写成负缓存，
    --    等机翻起来后 translate() 在负缓存处直接返回 nil，那条文本永远翻不到。
    if CONFIG.autoTranslate then
        AUTO.onTranslated = function()
            -- 队列消化得差不多了才重扫，避免每翻一条就整屏重扫
            if state.enabled and state.running and #AUTO.queue < 4 then
                pcall(sweepAll, state.usePlayerGui, state.usePlayerGui)
            end
        end
        AUTO.start()
    end

    -- 1) 先扫隐藏容器（gethui / CoreGui）
    local ok1, r1 = pcall(sweepAll, false)
    if not ok1 and CONFIG.verbose then
        warn("[UIT-CN] 主容器扫描异常: " .. tostring(r1))
    end

    -- 2) 一个菜单都没认出来 -> 退一步扫 PlayerGui（严格判定，绝不误翻游戏 HUD）
    local usedPlayerGui = false
    if CONFIG.usePlayerGuiFallback and countTargets() == 0 then
        local pg = getPlayerGui()
        if pg then
            usedPlayerGui = true
            if CONFIG.verbose then
                print("[UIT-CN] 隐藏容器内未发现菜单，已切换到 PlayerGui 严格扫描")
            end
            pcall(sweepContainer, pg, true)
        end
    end
    state.usePlayerGui = usedPlayerGui

    -- 3) 监听后续新建 / 重建的界面
    if CONFIG.watchNewUI then
        local list = containerList(usedPlayerGui)
        local pg = (usedPlayerGui or CONFIG.translatePlayerGui) and getPlayerGui() or nil
        for _, c in ipairs(list) do
            local strictPg = (pg ~= nil and c == pg) and not CONFIG.translatePlayerGui
            hookNewUI(c, strictPg)
        end
    end

    -- 4) 兜底重扫：自适应降频，手机上不会一直烧 CPU
    task.spawn(function()
        local t0 = os.clock()
        local gap = CONFIG.rescanInterval
        local idle = 0
        while state.running and (os.clock() - t0) < CONFIG.rescanSeconds do
            task.wait(gap)
            if not state.running then break end
            if state.enabled then
                local before = state.count
                pcall(sweepAll, usedPlayerGui, usedPlayerGui)
                if state.count == before then
                    idle += 1
                    if idle >= 2 then
                        gap = math.min(gap * 1.4, CONFIG.rescanMaxGap)
                        idle = 0
                    end
                else
                    idle = 0
                    gap = CONFIG.rescanInterval
                end
            end
        end
    end)

    if CONFIG.verbose then
        local hubs = countTargets()
        if hubs > 0 then
            print(("[UIT-CN] 已识别 %d 个界面，本次翻译 %d 个文本元素（挂载: %s）")
                :format(hubs, state.count, GUI_PARENT_NAME))
        else
            print(("[UIT-CN] 暂未发现脚本菜单，已进入监听：菜单打开后会自动翻译（挂载: %s）")
                :format(GUI_PARENT_NAME))
        end
    end
end

local api = {}
api.version = "2.0-mobile"
api.translate = translate
api.addPairs = addPairs
api.enable = function() setEnabled(true) end
api.disable = function() setEnabled(false) end
api.restore = function() return restoreAll() end
api.rescan = function()
    local n = sweepAll(state.usePlayerGui, state.usePlayerGui)
    if n == 0 and not state.usePlayerGui and CONFIG.usePlayerGuiFallback and countTargets() == 0 then
        local pg = getPlayerGui()
        if pg then pcall(sweepContainer, pg, true) end
    end
    return state.count
end
api.stats = function() return state.count, countTargets(), state.enabled end
api.parent = function() return GUI_PARENT_NAME end

--- 开关自动翻译
---   用法：getgenv().UIT_CN.auto(false)  关闭（只走词表）
---         getgenv().UIT_CN.auto(true)   打开
api.auto = function(on)
    CONFIG.autoTranslate = (on ~= false)
    if CONFIG.autoTranslate then
        if not AUTO.started then AUTO.start() else AUTO.enabled = true end
    else
        AUTO.enabled = false
    end
    return CONFIG.autoTranslate
end

--- 自动翻译状态：后端 / 已缓存条数 / 待翻队列 / 成功失败计数
api.autoStats = function() return AUTO.stats() end

--- 手动指定翻译后端：auto | google | mymemory | youdao
api.setProvider = function(name)
    if name == "auto" or PROVIDERS[name] then
        AUTO.provider = nil
        CONFIG.apiProvider = name
        return true
    end
    return false
end

--- 清空自动翻译缓存（换了后端或想重翻时用）
api.clearAutoCache = function()
    AUTO.cache, AUTO.pending, AUTO.queue = {}, {}, {}
    clearCache()
    return true
end

--- 诊断：列出每个界面的文本量 / 菜单分 / 判定结果 / 被卡在哪一条
--- 用法：getgenv().UIT_CN.diagnose()        只看汇总
---       getgenv().UIT_CN.diagnose(true)    连同实际英文文本一起打印
api.diagnose = function(showTexts)
    local T = { TextLabel = true, TextButton = true, TextBox = true }
    local total, okCnt = 0, 0

    print("[UIT-CN 诊断] 当前阈值：文本数 >= " .. CONFIG.minTextsForMenu
        .. " ｜ 菜单分 >= " .. CONFIG.minMenuScore
        .. " ｜ translatePlayerGui = " .. tostring(CONFIG.translatePlayerGui)
        .. " ｜ includeBillboard = " .. tostring(CONFIG.includeBillboard))

    local list = containerList(true)   -- 含 PlayerGui，看清全貌
    for _, c in ipairs(list) do
        local ok, kids = pcall(function() return c:GetChildren() end)
        if ok then
            for _, gui in ipairs(kids) do
                local cn = gui.ClassName
                if cn == "ScreenGui" or cn == "BillboardGui" or cn == "SurfaceGui" then
                    local tc, sc = analyze(gui)
                    if tc > 0 then
                        total += 1
                        local will, reason = false, "?"
                        if nameExcluded(gui.Name) then
                            reason = "内置黑名单"
                        elseif nameIncluded(gui.Name) then
                            will, reason = true, "强制纳入"
                        elseif cn == "BillboardGui" or cn == "SurfaceGui" then
                            if CONFIG.includeBillboard then
                                will, reason = true, "3D 标签已开启"
                            else
                                reason = "3D 标签未开启"
                            end
                        elseif tc < CONFIG.minTextsForMenu then
                            reason = "文本数 " .. tc .. " < " .. CONFIG.minTextsForMenu
                        elseif sc < CONFIG.minMenuScore then
                            reason = "菜单分 " .. sc .. " < " .. CONFIG.minMenuScore
                        else
                            will, reason = true, "打分通过"
                        end
                        if will then okCnt += 1 end
                        print(string.format("  %s %-24s [%s] 文本=%-3d 分=%-2d %s",
                            will and "[√]" or "[×]", tostring(gui.Name):sub(1, 24), cn, tc, sc, reason))
                        if showTexts then
                            local n = 0
                            for _, d in ipairs(gui:GetDescendants()) do
                                if T[d.ClassName] then
                                    local t = d.Text
                                    if type(t) == "string" and #t > 0 and t:match("%a") then
                                        n += 1
                                        if n <= 15 then
                                            print("        · " .. t:gsub("\n", "\\n"):sub(1, 68))
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    print(("[UIT-CN 诊断] 有文字的界面共 %d 个，会被翻译 %d 个"):format(total, okCnt))
    if okCnt == 0 and total > 0 then
        print("[UIT-CN 诊断] 一个都没通过？把目标 GUI 名字填进 CONFIG.forceInclude = { \"名字片段\" } 即可必翻")
    end
    return okCnt, total
end
api.stop = function()
    state.running = false
    AUTO.enabled = false          -- 停掉自动翻译 worker
    for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
    state.conns = {}
    newQueue, flushQueued = {}, false
    if toggleGui then pcall(function() toggleGui:Destroy() end) end
    toggleGui, toggleBtn = nil, nil
end

local prev = ENV.UIT_CN
if type(prev) == "table" and type(prev.stop) == "function" then pcall(prev.stop) end
ENV.UIT_CN = api

state.running = true
if CONFIG.autoApply then
    local ok, err = pcall(start)
    if not ok then warn("[UIT-CN] 启动失败: " .. tostring(err)) end
end
