--[[
    ============================================================
    UI 中文化 · 通用版  (Universal Roblox UI Translator)
    English -> 简体中文，实时翻译任意注入脚本的菜单界面
    ============================================================

    适用：任意执行器脚本菜单（外挂菜单 / 工具面板 / Hub / 通知窗），
          不绑定某个具体脚本；也能翻游戏自带 HUD（改配置即可）。

    能力：
      · 自动识别：扫描 gethui() / CoreGui，靠「文本量 + 菜单词命中」打分
        判定哪个 GUI 是脚本菜单，Roblox 自带 UI 自动排除
      · 三层翻译：精确整串 -> 数字/计时规则 -> 多词短语 -> 单词兜底(带词形还原)
      · 长句保护：不认识的英文长句保持原文，避免翻出「自动 Farm」这种半截话
      · 富文本安全：<font color=...> 之类标签原样保留，只翻文字
      · 动态跟随：切标签、重开面板、脚本自己改文字，都会自动补翻
      · 可逆：右上角「中/EN」按钮一键切换，原文全部缓存

    用法：
      执行即可。运行后：
        getgenv().UIT_CN.restore()      还原英文
        getgenv().UIT_CN.enable()       重新翻译
        getgenv().UIT_CN.rescan()       立即重新扫描
        getgenv().UIT_CN.addPairs({ {"Auto Fish","自动钓鱼"} })  追加词条
        getgenv().UIT_CN.stop()         停止并移除按钮

    想加自己的翻译：往 EXACT_PAIRS 里加 { "English", "中文" } 即可，
    单词会进单词表，多词会进短语表（大小写不敏感）。
    ============================================================
]]

local CONFIG = {
    autoApply        = true,   -- 执行后立即翻译
    showToggle       = true,   -- 显示浮动「中/EN」按钮
    translatePlayerGui = false, -- true = 连游戏本身 HUD 一起翻
    watchNewUI       = true,   -- 监听后续新建 / 重建的界面
    rescanSeconds    = 300,    -- 兜底重扫持续时间（秒）
    rescanInterval   = 1.5,    -- 兜底重扫间隔（秒）
    minTextsForMenu  = 24,     -- 判定菜单：GUI 内文本元素下限
    minMenuScore     = 3,      -- 判定菜单：命中菜单特征词的数量下限
    strictNoMixed    = true,   -- 严格模式：译文里还有没翻掉的英文词就整条保留原文（不出半中半英）
    maxLeftRatio     = 0.4,    -- 兼容旧配置，留作参考
    includeNames     = {},     -- 强制纳入的 GUI 名（小写子串），如 { "hub", "menu" }
    extraExclude     = {},     -- 额外排除的 GUI 名（小写）
    verbose          = true,
}

----------------------------------------------------------------
-- 1. 词库：通用界面 / 功能 / 设置术语
----------------------------------------------------------------
local EXACT_PAIRS = {
    -- 框架与标签
    { "Menu", "菜单" }, { "Main", "主界面" }, { "Home", "首页" }, { "General", "常规" },
    { "Settings", "设置" }, { "Setting", "设置" }, { "Config", "配置" }, { "Configs", "配置" },
    { "Configuration", "配置" }, { "Options", "选项" }, { "Advanced", "高级" }, { "Extras", "扩展" },
    { "Misc", "杂项" }, { "Miscellaneous", "杂项" }, { "Utilities", "实用工具" }, { "Utility", "工具" },
    { "Tools", "工具" }, { "Features", "功能" }, { "Modules", "模块" }, { "Plugins", "插件" },
    { "Debug", "调试" }, { "Developer", "开发者" }, { "About", "关于" }, { "Info", "信息" },
    { "Credits", "制作名单" }, { "Version", "版本" }, { "Update", "更新" }, { "Changelog", "更新日志" },
    { "Language", "语言" }, { "Theme", "主题" }, { "Dark", "深色" }, { "Light", "浅色" },
    { "Profile", "配置文件" }, { "Profiles", "配置文件" }, { "Preset", "预设" }, { "Presets", "预设" },
    { "Slot", "存档位" }, { "Slots", "存档位" }, { "Session", "会话" }, { "Status", "状态" },
    { "State", "状态" }, { "Uptime", "运行时长" }, { "Log", "日志" }, { "Logs", "日志" },
    { "Console", "控制台" }, { "Notifications", "通知" }, { "Notification", "通知" },
    { "Hub", "中心" }, { "Script Hub", "脚本库" }, { "Scripts", "脚本" }, { "Script", "脚本" },

    -- 按钮 / 操作
    { "Save", "保存" }, { "Load", "加载" }, { "Reset", "重置" }, { "Restore", "恢复" },
    { "Default", "默认" }, { "Apply", "应用" }, { "Confirm", "确认" }, { "Cancel", "取消" },
    { "Close", "关闭" }, { "Open", "打开" }, { "Exit", "退出" }, { "Back", "返回" },
    { "Next", "下一个" }, { "Previous", "上一个" }, { "Continue", "继续" }, { "OK", "确定" },
    { "Yes", "是" }, { "No", "否" }, { "Done", "完成" }, { "Submit", "提交" },
    { "Send", "发送" }, { "Copy", "复制" }, { "Paste", "粘贴" }, { "Clear", "清空" },
    { "Delete", "删除" }, { "Remove", "移除" }, { "Add", "添加" }, { "Create", "创建" },
    { "Edit", "编辑" }, { "Rename", "重命名" }, { "Select", "选择" }, { "Select All", "全选" },
    { "Selected", "已选" }, { "Search", "搜索" }, { "Find", "查找" }, { "Filter", "筛选" },
    { "Sort", "排序" }, { "Refresh", "刷新" }, { "Reload", "重载" }, { "Import", "导入" },
    { "Export", "导出" }, { "Share", "分享" }, { "Backup", "备份" }, { "Upload", "上传" },
    { "Download", "下载" }, { "Retry", "重试" }, { "Try Again", "重试" }, { "Undo", "撤销" },

    -- 开关状态
    { "Toggle", "开关" }, { "Enable", "启用" }, { "Disable", "禁用" }, { "Enabled", "已启用" },
    { "Disabled", "已禁用" }, { "On", "开" }, { "Off", "关" }, { "True", "真" }, { "False", "假" },
    { "Active", "已激活" }, { "Inactive", "未激活" }, { "Locked", "已锁定" }, { "Unlocked", "已解锁" },
    { "Premium", "高级版" }, { "Free", "免费" }, { "Beta", "测试版" }, { "Alpha", "内测版" },

    -- 输入 / 按键
    { "Key", "按键" }, { "Keybind", "快捷键" }, { "Keybinds", "快捷键" }, { "Hotkey", "热键" },
    { "Hotkeys", "热键" }, { "Bind", "绑定" }, { "Unbind", "解绑" }, { "Press", "按下" },
    { "Hold", "长按" }, { "Click", "点击" }, { "Double Click", "双击" }, { "Right Click", "右键" },
    { "Left Click", "左键" }, { "Drag", "拖动" }, { "Drop", "丢弃" }, { "Window Key", "窗口按键" },

    -- 数值 / 参数
    { "Name", "名称" }, { "Type", "类型" }, { "Value", "数值" }, { "Amount", "数量" },
    { "Limit", "限制" }, { "Min", "最小" }, { "Max", "最大" }, { "Random", "随机" },
    { "Randomize", "随机化" }, { "Manual", "手动" }, { "Auto", "自动" }, { "Always", "始终" },
    { "Never", "从不" }, { "Once", "一次" }, { "Repeat", "重复" }, { "Loop", "循环" },
    { "Infinite", "无限" }, { "Unlimited", "无限" }, { "Time", "时间" }, { "Timer", "计时器" },
    { "Delay", "延迟" }, { "Interval", "间隔" }, { "Duration", "持续时间" }, { "Cooldown", "冷却" },
    { "Speed", "速度" }, { "Rate", "速率" }, { "Size", "大小" }, { "Scale", "缩放" },
    { "Distance", "距离" }, { "Range", "范围" }, { "Radius", "半径" }, { "Height", "高度" },
    { "Width", "宽度" }, { "Angle", "角度" }, { "Multiplier", "倍率" }, { "Percent", "百分比" },
    { "Percentage", "百分比" }, { "Chance", "概率" }, { "Priority", "优先级" }, { "Order", "顺序" },

    -- 数值单位
    { "Studs", "格" }, { "Seconds", "秒" }, { "Milliseconds", "毫秒" }, { "Minutes", "分钟" },
    { "Hours", "小时" }, { "HP", "生命" }, { "MP", "法力" }, { "XP", "经验" },
    { "Coins", "金币" }, { "Gems", "宝石" }, { "Cash", "现金" }, { "Money", "金钱" },
    { "Tokens", "代币" }, { "Points", "积分" }, { "Score", "分数" }, { "Rank", "排名" },
    { "Tier", "阶级" }, { "Stage", "关卡" }, { "Wave", "波数" }, { "Round", "回合" },
    { "Match", "对局" }, { "Level", "等级" }, { "Exp", "经验" }, { "Ping", "延迟" }, { "FPS", "帧率" },

    -- 对象 / 场景
    { "Game", "游戏" }, { "Games", "游戏" }, { "Server", "服务器" }, { "Region", "地区" },
    { "Player", "玩家" }, { "Players", "玩家" }, { "Self", "自己" }, { "Others", "其他人" },
    { "Enemy", "敌人" }, { "Enemies", "敌人" }, { "Team", "队伍" }, { "Teammates", "队友" },
    { "Friends", "好友" }, { "All", "全部" }, { "None", "无" }, { "Everyone", "所有人" },
    { "Target", "目标" }, { "Targets", "目标" }, { "Nearest", "最近" }, { "Closest", "最近" },
    { "Farthest", "最远" }, { "Character", "角色" }, { "Avatar", "形象" }, { "Inventory", "背包" },
    { "Backpack", "背包" }, { "Shop", "商店" }, { "Store", "商店" }, { "Market", "市场" },
    { "Trade", "交易" }, { "Weapon", "武器" }, { "Weapons", "武器" }, { "Item", "物品" },
    { "Items", "物品" }, { "Armor", "护甲" }, { "Shield", "护盾" }, { "Ammo", "弹药" },

    -- 属性
    { "Health", "生命" }, { "Mana", "法力" }, { "Stamina", "体力" }, { "Energy", "能量" },
    { "Damage", "伤害" }, { "Defense", "防御" }, { "Attack", "攻击" }, { "Crit", "暴击" },
    { "Critical", "暴击" }, { "Luck", "幸运" }, { "Strength", "力量" }, { "Agility", "敏捷" },
    { "Intelligence", "智力" }, { "Armor Boost", "护甲加成" }, { "Health Boost", "生命加成" },
    { "Damage Boost", "伤害加成" }, { "Life Steal", "吸血" }, { "Thorns", "荆棘" },

    -- 动作
    { "Jump", "跳跃" }, { "Walk", "行走" }, { "Run", "奔跑" }, { "Sprint", "冲刺" },
    { "Dash", "疾跑" }, { "Fly", "飞行" }, { "Swim", "游泳" }, { "Climb", "攀爬" },
    { "Crouch", "蹲下" }, { "Glide", "滑翔" }, { "Teleport", "传送" }, { "Teleports", "传送" },
    { "Movement", "移动" }, { "Sell", "出售" }, { "Buy", "购买" }, { "Purchase", "购买" },
    { "Equip", "装备" }, { "Unequip", "卸下" }, { "Use", "使用" }, { "Consume", "消耗" },
    { "Pickup", "拾取" }, { "Collect", "收集" }, { "Gather", "采集" }, { "Harvest", "收获" },
    { "Mine", "挖矿" }, { "Chop", "砍伐" }, { "Fish", "钓鱼" }, { "Cook", "烹饪" },
    { "Craft", "制作" }, { "Upgrade", "升级" }, { "Refine", "精炼" }, { "Merge", "合成" },
    { "Unlock", "解锁" }, { "Redeem", "兑换" }, { "Claim", "领取" }, { "Reward", "奖励" },
    { "Rewards", "奖励" }, { "Quest", "任务" }, { "Quests", "任务" }, { "Mission", "任务" },
    { "Missions", "任务" }, { "Task", "任务" }, { "Tasks", "任务" }, { "Objective", "目标" },
    { "Daily", "每日" }, { "Weekly", "每周" }, { "Boss", "首领" }, { "Dungeon", "地下城" },
    { "Raid", "突袭" }, { "Raids", "突袭" }, { "Arena", "竞技场" }, { "Party", "队伍" },
    { "Lobby", "大厅" }, { "Spawn", "出生点" }, { "Map", "地图" }, { "World", "世界" },
    { "Zone", "区域" }, { "Area", "区域" }, { "Location", "位置" }, { "Waypoint", "传送点" },
    { "Marker", "标记" }, { "Checkpoint", "检查点" }, { "Combat", "战斗" }, { "Farming", "刷取" },
    { "Farm", "挂机" }, { "Fishing", "钓鱼" }, { "Survival", "生存" }, { "Recovery", "恢复" },

    -- 外挂功能
    { "Visuals", "视觉" }, { "Render", "渲染" }, { "Graphics", "画面" }, { "ESP", "透视" },
    { "Box ESP", "方框透视" }, { "Name ESP", "名字透视" }, { "Health ESP", "血量透视" },
    { "Tracer", "追踪线" }, { "Tracers", "追踪线" }, { "Chams", "骨骼透视" }, { "Highlight", "高亮" },
    { "Aimbot", "自瞄" }, { "Aim", "瞄准" }, { "Aim Assist", "辅助瞄准" }, { "Silent Aim", "静默瞄准" },
    { "Trigger Bot", "自动开火" }, { "Auto Aim", "自动瞄准" }, { "FOV", "视野范围" },
    { "Smoothing", "平滑度" }, { "Sensitivity", "灵敏度" }, { "Prediction", "预判" },
    { "Hitbox", "判定框" }, { "Hitboxes", "判定框" }, { "Team Check", "队伍检测" },
    { "Wall Check", "墙体检测" }, { "Visible Check", "可见检测" }, { "Whitelist", "白名单" },
    { "Blacklist", "黑名单" }, { "Exploit", "漏洞" }, { "Exploits", "漏洞" },
    { "Anti-Cheat", "反作弊" }, { "Anti-Ban", "防封" }, { "Anti Kick", "防踢" },
    { "Anti-AFK", "防挂机" }, { "Bypass", "绕过" }, { "God Mode", "无敌" }, { "Godmode", "无敌" },
    { "Noclip", "穿墙" }, { "No Clip", "穿墙" }, { "Fullbright", "全亮" }, { "No Fog", "去雾" },
    { "Walk Speed", "移动速度" }, { "WalkSpeed", "移动速度" }, { "Jump Power", "跳跃力" },
    { "JumpPower", "跳跃力" }, { "Infinite Jump", "无限跳跃" }, { "Infinite Ammo", "无限弹药" },
    { "Fire Rate", "射速" }, { "Firerate", "射速" }, { "Recoil", "后坐力" }, { "Spread", "散布" },
    { "Fast Attack", "快速攻击" }, { "Instant", "瞬间" }, { "Fast", "快速" }, { "Slow", "慢速" },
    { "Tween", "缓动" }, { "Orbit", "环绕" }, { "Hover", "悬停" }, { "Highlight Target", "高亮目标" },

    -- 自动化
    { "Auto Farm", "自动挂机" }, { "Auto Click", "自动点击" }, { "Auto Clicker", "自动点击器" },
    { "Auto Fish", "自动钓鱼" }, { "Auto Quest", "自动任务" }, { "Auto Sell", "自动出售" },
    { "Auto Buy", "自动购买" }, { "Auto Pickup", "自动拾取" }, { "Auto Collect", "自动收集" },
    { "Auto Use", "自动使用" }, { "Auto Potion", "自动药水" }, { "Auto Dodge", "自动闪避" },
    { "Auto Parry", "自动格挡" }, { "Auto Block", "自动格挡" }, { "Auto Heal", "自动回血" },
    { "Auto Respawn", "自动复活" }, { "Auto Rejoin", "自动重进" }, { "Auto Reconnect", "自动重连" },
    { "Auto Skip", "自动跳过" }, { "Auto Equip", "自动装备" }, { "Auto Upgrade", "自动升级" },
    { "Auto Roll", "自动抽取" }, { "Auto Gather", "自动采集" }, { "Auto Attack", "自动攻击" },
    { "Auto Play", "自动开始" }, { "Auto Claim", "自动领取" }, { "Auto Reward", "自动领取" },
    { "Auto Ability", "自动技能" }, { "Auto Teleport", "自动传送" },

    -- 状态提示
    { "Loading", "加载中" }, { "Loaded", "已加载" }, { "Ready", "就绪" }, { "Waiting", "等待中" },
    { "Success", "成功" }, { "Failed", "失败" }, { "Error", "错误" }, { "Warning", "警告" },
    { "Connected", "已连接" }, { "Disconnected", "已断开" }, { "Online", "在线" }, { "Offline", "离线" },
    { "No Results", "无结果" }, { "Not Found", "未找到" }, { "Empty", "空" }, { "Unknown", "未知" },
    { "Coming Soon", "即将推出" }, { "Are You Sure", "确定吗" }, { "Reconnect", "重连" },
    { "Rejoin", "重进" }, { "Owner", "所有人" }, { "Admin", "管理员" }, { "User", "用户" },
    { "Username", "用户名" }, { "Password", "密码" }, { "Discord", "Discord" }, { "Executor", "执行器" },

    -- 游戏包：Generic Pixel Blade Hub（不需要可整段删掉）
    { "KEYLESS - SCAM IF KEY NEEDED", "无密钥 · 要密钥就是骗局" },
    { "created by adn", "作者 adn" }, { "Unload Script", "卸载脚本" }, { "Menu Launcher", "菜单启动器" },
    { "Search settings", "搜索设置" }, { "Wishes", "愿望" }, { "Chests", "宝箱" },
    { "Dark Keys", "暗黑钥匙" }, { "Charms", "护符" }, { "Charm", "护符" }, { "Donate", "赞助" },
    { "Kill Aura", "击杀光环" }, { "Swing every (s)", "挥动间隔 (秒)" }, { "Radius (studs)", "半径 (格)" },
    { "Hit props", "攻击场景物件" }, { "Use below (% HP)", "低于时使用 (% 生命)" },
    { "Movement", "移动方式" }, { "Side", "侧向" }, { "Above", "上方" }, { "Distance (studs)", "距离 (格)" },
    { "Tween speed (studs/s)", "缓动速度 (格/秒)" }, { "Idle Height (studs)", "悬停高度 (格)" },
    { "Potato Graphics", "土豆画质" }, { "Regular FPS Boost", "常规帧率提升" },
    { "Disable 3D rendering", "关闭 3D 渲染" }, { "Highlight Dark Chests", "高亮暗黑宝箱" },
    { "Pause All", "全部暂停" }, { "Pause key", "暂停按键" }, { "Average run", "平均用时" },
    { "Recent runs", "最近记录" }, { "No runs yet this session", "本局暂无记录" },
    { "Ended", "已结束" }, { "Running", "进行中" }, { "In the run", "局内" },
    { "Waiting for the game state", "等待游戏状态" }, { "Deaths", "死亡次数" }, { "Catches", "钓获" },
    { "Classic Pole", "经典钓竿" }, { "Equipped", "已装备" }, { "Anti-AFK", "防挂机" },
    { "Auto Escape Grabs", "自动挣脱抓取" }, { "No active features", "暂无激活功能" },
    { "Farm Plan: W1 Normal", "挂机计划: W1 普通" }, { "Follow the farm plan", "按挂机计划执行" },
    { "Farm Together", "一起挂机" }, { "Force Group", "强制组队" }, { "Auto world", "自动世界" },
    { "Where", "位置" }, { "Leave at wave", "波次离开" }, { "Leave at (chests)", "剩余宝箱数离开" },
    { "Leave runs to open", "留几次开箱" }, { "Leave runs to turn in", "留几次交任务" },
    { "Move to safe spot", "移动到安全点" }, { "Stall time (s)", "停滞时间 (秒)" },
    { "Wait limit (s)", "等待上限 (秒)" }, { "Target classes", "目标职业" },
    { "Morvik Teammate Rescue", "Morvik 队友救援" }, { "Show on Hover", "悬停显示" },
    { "Grasslands", "草原" }, { "Island Details", "岛屿详情" }, { "Auto Continue", "自动继续" },
    { "Auto Pick Card", "自动选卡" }, { "Auto Replay", "自动重开" }, { "Auto Skip Cutscenes", "自动跳过过场" },
    { "Auto Revive", "自动复活" }, { "Auto Merge Books", "自动合成书籍" }, { "Auto Open Chests", "自动开宝箱" },
    { "Open All Chests", "打开所有宝箱" }, { "Auto Open Dark Chests", "自动开暗黑宝箱" },
    { "Auto Open Wishes", "自动开愿望" }, { "Auto Buy Daily Shop", "自动购买每日商店" },
    { "Auto Charm Prize", "自动护符奖励" }, { "Charm Prize Priority", "护符奖励优先级" },
    { "Configure Charm Prize", "配置护符奖励" }, { "Auto Equip Best", "自动装备最优" },
    { "Auto Equip Charm", "自动装备护符" }, { "Auto Execute", "自动处决" }, { "Class roll", "职业抽取" },
    { "Cards", "卡片" }, { "Card ranks", "卡片等级" }, { "Your charms", "你的护符" },
    { "No charms yet", "暂无护符" }, { "Use selected charm", "使用所选护符" },
    { "Most Luck", "最高幸运" }, { "Most Owned", "拥有最多" }, { "Fallback to most owned", "回退到拥有最多" },
    { "Ultimate Charm", "终极护符" }, { "Equip Best", "装备最优" }, { "Reaper (0.5%)", "死神 (0.5%)" },
    { "Bait", "鱼饵" }, { "Bait Fallback", "鱼饵备选" }, { "Fishing rod", "钓竿" },
    { "Fast Fishing", "快速钓鱼" }, { "Worms", "蠕虫" }, { "Potions", "药水" },
    { "Potion Restock", "药水补货" }, { "Restock below", "低于时补货" },
    { "Auto-buy potions", "自动购买药水" }, { "Auto Upgrade Rod", "自动升级钓竿" },
    { "Auto Upgrade Stash", "自动升级仓库" }, { "Upgrade All", "全部升级" },
    { "Upgrade Check", "升级检查" }, { "Upgrade Plan", "升级计划" }, { "Upgrade rarities", "升级稀有度" },
    { "Items maxed", "已满级物品" }, { "Nothing left to max", "已无可提升项" },
    { "No Legendary drops found for this world", "本世界没有传说掉落" },
    { "Quality Check", "品质检查" }, { "Melt Rings", "熔炼戒指" }, { "Melt Ring Tier", "熔炼戒指阶级" },
    { "Melt Ring Type", "熔炼戒指类型" }, { "Melt quality at or below", "熔炼品质低于或等于" },
    { "Refine All", "全部精炼" }, { "Refine Ring Type", "精炼戒指类型" }, { "Unveil Rings", "揭示戒指" },
    { "Auto Unveil Pages", "自动揭示书页" }, { "Rings", "戒指" }, { "Rings per press", "每次按键戒指数" },
    { "Rarity", "稀有度" }, { "Item rarities", "物品稀有度" }, { "Common, Rare +1", "普通、稀有 +1" },
    { "Legendary", "传说" }, { "Heroic", "英雄" }, { "Vaulted", "已封存" },
    { "Nightmare", "噩梦" }, { "Dungeon - Normal", "地下城 · 普通" }, { "Raid waves", "突袭波数" },
    { "Max players", "最大玩家数" }, { "Armory", "军械库" }, { "Element Circle", "元素环" },
    { "Flame Element", "火焰元素" }, { "Frost Element", "冰霜元素" }, { "Poison Element", "毒素元素" },
    { "Rage Spirits", "狂怒之灵" }, { "Use luck circles", "使用幸运圈" },
    { "Critical Boost", "暴击加成" }, { "Spirit Capacity", "灵魂容量" },
    { "Speed (deg/s)", "速度 (度/秒)" }, { "Difficulty", "难度" }, { "Client", "客户端" },
    { "Refresh list", "刷新列表" }, { "Sell everything", "出售全部" }, { "Sell Stash Now", "立即出售仓库" },
    { "Buy chests", "购买宝箱" }, { "Redeem Codes", "兑换码" }, { "Dynamic Island", "灵动岛" },
    { "UI Scale (%)", "UI 缩放 (%)" }, { "Click or press Delete to open", "点击或按 Delete 打开" },
    { "Reset order", "重置顺序" }, { "Clear all", "清空全部" }, { "Clear auto-load", "清空自动加载" },
    { "Set auto-load", "设置自动加载" }, { "Auto-load", "自动加载" }, { "Auto-sell", "自动出售" },
    { "Share code", "分享码" }, { "No config loaded", "未加载配置" }, { "Delete Config", "删除配置" },
    { "Copy Config", "复制配置" }, { "Apply Config", "应用配置" }, { "Config Sharing", "配置共享" },
    { "Configure", "配置" },     { "Dungeon Lobby", "地下城大厅" }, { "Generic Pixel Blade Hub", "通用像素之刃 Hub" },

    -- 通用补充（高频零碎词）
    { "List", "列表" }, { "Set", "设置" }, { "Found", "找到" }, { "Result", "结果" },
    { "Mode", "模式" }, { "Pause", "暂停" }, { "Resume", "继续" }, { "Runs", "次数" },
    { "Highest", "最高" }, { "Lowest", "最低" }, { "Skip", "跳过" }, { "Epic", "史诗" },
    { "Dealer", "商人" }, { "Iron", "铁" }, { "Pole", "钓竿" }, { "Rarity Boost", "稀有度加成" },
    { "No Results Found", "未找到结果" }, { "Farm Plan", "挂机计划" },
    { "Normal", "普通" }, { "Hard", "困难" }, { "Easy", "简单" }, { "Expert", "专家" },
    { "Master", "大师" }, { "Easy Mode", "简单模式" }, { "Hard Mode", "困难模式" },
    { "WASD or joystick to fly; Space up, Alt down; look up/down on phones", "WASD 或摇杆飞行；空格上升、Alt 下降；手机上抬头/低头" },
    { "Priority: 1 Highest, 3 Lowest; 0 Skip", "优先级: 1 最高，3 最低；0 跳过" },
    { "Earn Wishes from Morvik (W5), fishing, daily login or purchases.", "通过 Morvik(W5)、钓鱼、每日登录或购买获得愿望。" },
    { "Takes your top-ranked unmaxed Legendary; else the lowest-tier unmaxed item; else random", "优先取未满级的最高阶传说；否则取最低阶未满级物品；否则随机" },
    { "Will equip Super Charm [Epic] at the dealer", "在商人处自动装备超级护符 [史诗]" },

    -- ===== 扩充词库 v2：补齐「半英半中」的漏词 =====

    -- 程度 / 前缀
    { "Super", "超级" }, { "Ultra", "终极" }, { "Mega", "巨型" }, { "Extreme", "极限" },
    { "Absolute", "绝对" }, { "Total", "总计" }, { "Partial", "部分" }, { "Fully", "完全" },
    { "Half", "一半" }, { "Double", "双倍" }, { "Triple", "三倍" }, { "Extra", "额外" },
    { "Bonus", "额外加成" }, { "Boost", "提升" }, { "Reduce", "降低" }, { "Increase", "增加" },
    { "Decrease", "减少" }, { "Max", "最大" }, { "Min", "最小" }, { "Medium", "中等" },
    { "Low", "低" }, { "High", "高" }, { "Tiny", "极小" }, { "Huge", "巨大" },
    { "Full", "完整" }, { "Short", "短" }, { "Long", "长" }, { "Basic", "基础" },
    { "Simple", "简单" }, { "Complex", "复杂" }, { "Fixed", "固定" }, { "Dynamic", "动态" },
    { "Custom", "自定义" }, { "Precise", "精准" }, { "Accurate", "精准" }, { "Smart", "智能" },
    { "Stable", "稳定" }, { "Smooth", "平滑" }, { "Rapid", "快速" }, { "Safe", "安全" },
    { "Unsafe", "不安全" }, { "Danger", "危险" }, { "Risky", "有风险" }, { "Silent", "静默" },
    { "Legit", "拟真" }, { "Rage", "暴力" }, { "Blatant", "明显" }, { "Visible", "可见" },
    { "Hidden", "隐藏" }, { "Reverse", "反向" }, { "Invert", "反转" }, { "Swap", "交换" },
    { "Mirror", "镜像" }, { "Flip", "翻转" }, { "Rotate", "旋转" }, { "Zoom", "缩放" },
    { "Always On", "常开" }, { "Always Off", "常关" }, { "On Top", "置顶" }, { "Toggle On", "开启" },
    { "Turn On", "开启" }, { "Turn Off", "关闭" }, { "Turned On", "已开启" }, { "Turned Off", "已关闭" },

    -- 常用动词
    { "Now", "立即" }, { "Soon", "即将" }, { "Later", "稍后" }, { "Disconnect", "断开" },
    { "Connect", "连接" }, { "Connecting", "连接中" }, { "Reconnecting", "重连中" },
    { "Kick", "踢出" }, { "Ban", "封禁" }, { "Detect", "检测" }, { "Detected", "已检测" },
    { "Ignore", "忽略" }, { "Ignored", "已忽略" }, { "Follow", "跟随" }, { "Chase", "追击" },
    { "Dodge", "闪避" }, { "Parry", "格挡" }, { "Block", "格挡" }, { "Grab", "抓取" },
    { "Escape", "挣脱" }, { "Revive", "复活" }, { "Respawn", "重生" }, { "Start", "开始" },
    { "Stop", "停止" }, { "Pause", "暂停" }, { "Finish", "完成" }, { "Complete", "完成" },
    { "Completed", "已完成" }, { "Abort", "中止" }, { "Accept", "接受" }, { "Decline", "拒绝" },
    { "Allow", "允许" }, { "Deny", "拒绝" }, { "Request", "请求" }, { "Respond", "回应" },
    { "Reply", "回复" }, { "Mute", "静音" }, { "Unmute", "取消静音" }, { "Report", "举报" },
    { "Mark", "标记" }, { "Track", "追踪" }, { "Scan", "扫描" }, { "Sync", "同步" },
    { "Verify", "验证" }, { "Check", "检查" }, { "Test", "测试" }, { "Try", "尝试" },
    { "Train", "训练" }, { "Summon", "召唤" }, { "Cast", "施放" }, { "Charge", "蓄力" },
    { "Shoot", "射击" }, { "Fire", "开火" }, { "Reload", "重装" }, { "Throw", "投掷" },
    { "Place", "放置" }, { "Build", "建造" }, { "Destroy", "摧毁" }, { "Break", "破坏" },
    { "Defend", "防御" }, { "Heal", "治疗" }, { "Protect", "保护" }, { "Avoid", "躲避" },
    { "Skip", "跳过" }, { "Skipped", "已跳过" }, { "Wait", "等待" }, { "Waiting", "等待中" },
    { "Return", "返回" }, { "Go", "前往" }, { "Move", "移动" }, { "Stay", "停留" },
    { "Enter", "进入" }, { "Leave", "离开" }, { "Join", "加入" },
    { "Buy", "购买" }, { "Sell", "出售" }, { "Open", "打开" }, { "Close", "关闭" },
    { "Show", "显示" }, { "Hide", "隐藏" }, { "Lower", "降低" }, { "Raise", "提高" },
    { "Sound", "声音" }, { "Sounds", "声音" }, { "Music", "音乐" }, { "Volume", "音量" },
    { "Particle", "粒子" }, { "Particles", "粒子" }, { "Door", "门" }, { "Doors", "门" },
    { "Static", "静态" }, { "Exploiter", "作弊者" }, { "Exploiters", "作弊者" },
    { "Common", "普通" }, { "Uncommon", "罕见" }, { "Rare", "稀有" }, { "Mythic", "神话" },
    { "Divine", "神圣" }, { "Unique", "独特" }, { "Special", "特殊" },
    { "Nothing here", "这里什么都没有" },
    { "Hover on desktop or hold on mobile to reveal quick info", "桌面端悬停、移动端长按可查看快速信息" },

    -- 通用菜单高频词（来自未调优菜单的实测缺口）
    { "New", "新建" }, { "Shake", "震动" }, { "Mouse", "鼠标" }, { "Crosshair", "准星" },
    { "Accent", "强调" }, { "Duplicate", "复制" }, { "Clipboard", "剪贴板" }, { "View", "查看" },
    { "Bug", "问题" }, { "Unload", "卸载" }, { "Hop", "跳转" }, { "Base", "基地" },
    { "Anchor", "锚定" }, { "Ghost", "幽灵" }, { "Gravity", "重力" }, { "Release", "释放" },
    { "Kill", "击杀" }, { "Dead", "死亡" }, { "Dismiss", "关闭" }, { "Streamer", "主播" },
    { "Timeout", "超时" }, { "Count", "数量" }, { "Verbose", "详细" }, { "Logging", "日志" },
    { "Frame", "帧" }, { "Camera", "镜头" }, { "Style", "样式" }, { "Rich Presence", "在线状态" },
    { "Report a Bug", "报告问题" }, { "Request a Feature", "请求新功能" },
    { "Create New Config", "新建配置" }, { "Duplicate Config", "复制配置" },
    { "Master Volume", "主音量" }, { "Spawn Item", "生成物品" },
    { "Blacklist Player", "拉黑玩家" }, { "Ignore Dead", "忽略已死亡" },
    { "Cheater", "作弊者" }, { "Cheaters", "作弊者" }, { "Hacker", "黑客" },
    { "Hackers", "黑客" }, { "Alt", "小号" }, { "Alts", "小号" },

    -- 名词 / 对象
    { "Effect", "效果" }, { "Effects", "效果" }, { "Aura", "光环" }, { "Rune", "符文" },
    { "Runes", "符文" }, { "Ore", "矿石" }, { "Wood", "木材" }, { "Stone", "石头" },
    { "Food", "食物" }, { "Water", "水" }, { "Seed", "种子" }, { "Seeds", "种子" },
    { "Crop", "作物" }, { "Crops", "作物" }, { "Pet", "宠物" }, { "Pets", "宠物" },
    { "Mount", "坐骑" }, { "Egg", "蛋" }, { "Eggs", "蛋" }, { "Hatch", "孵化" },
    { "Skin", "皮肤" }, { "Skins", "皮肤" }, { "Cosmetic", "装饰" }, { "Cosmetics", "装饰" },
    { "Emote", "表情" }, { "Badge", "徽章" }, { "Title", "称号" }, { "Titles", "称号" },
    { "Tag", "标签" }, { "Chest", "宝箱" }, { "Crate", "箱子" }, { "Crates", "箱子" },
    { "Loot", "战利品" }, { "Drop", "掉落" }, { "Drops", "掉落" }, { "Spawner", "刷新点" },
    { "Portal", "传送门" }, { "Island", "岛屿" }, { "Cave", "洞穴" }, { "Forest", "森林" },
    { "Desert", "沙漠" }, { "Snow", "雪原" }, { "Ocean", "海洋" }, { "Beach", "海滩" },
    { "Mountain", "山脉" }, { "Village", "村庄" }, { "City", "城市" }, { "Castle", "城堡" },
    { "Monster", "怪物" }, { "Monsters", "怪物" }, { "Mobs", "怪物" }, { "Mob", "怪物" },
    { "Ally", "盟友" }, { "Allies", "盟友" }, { "NPC", "NPC" }, { "Rebirth", "重生" },
    { "Prestige", "转生" }, { "Ascend", "飞升" }, { "Evolve", "进化" }, { "Evolution", "进化" },
    { "Mutation", "变异" }, { "Fusion", "融合" }, { "Recipe", "配方" }, { "Blueprint", "图纸" },
    { "Material", "材料" }, { "Materials", "材料" }, { "Rod", "钓竿" }, { "Stash", "仓库" },
    { "Vault", "金库" }, { "Wardrobe", "衣柜" }, { "Outfit", "套装" }, { "Gear", "装备" },
    { "Accessory", "饰品" }, { "Consumable", "消耗品" }, { "Potion", "药水" },
    { "Owned", "拥有" }, { "Owns", "拥有" }, { "Unveil", "揭示" }, { "Unveils", "揭示" },
    { "Automatically", "自动" }, { "Manual", "手动" }, { "Points", "积分" },

    -- 界面控件
    { "Dashboard", "控制面板" }, { "Panel", "面板" }, { "Window", "窗口" }, { "Tab", "标签页" },
    { "Tabs", "标签页" }, { "Section", "栏目" }, { "Sections", "栏目" }, { "Group", "分组" },
    { "Groups", "分组" }, { "Category", "分类" }, { "Categories", "分类" }, { "Submenu", "子菜单" },
    { "Slider", "滑块" }, { "Checkbox", "复选框" }, { "Dropdown", "下拉框" }, { "Input", "输入框" },
    { "Label", "标签" }, { "Text", "文本" }, { "Description", "说明" }, { "Tooltip", "提示" },
    { "Preview", "预览" }, { "Layout", "布局" }, { "Position", "位置" }, { "Alignment", "对齐" },
    { "Opacity", "不透明度" }, { "Transparency", "透明度" }, { "Color", "颜色" },
    { "Colors", "颜色" }, { "Font", "字体" }, { "Icon", "图标" }, { "Icons", "图标" },
    { "Minimize", "最小化" }, { "Maximize", "最大化" }, { "Prefix", "前缀" },
    { "Suffix", "后缀" }, { "Command", "指令" }, { "Commands", "指令" }, { "Help", "帮助" },
    { "Support", "支持" }, { "Documentation", "文档" }, { "Tutorial", "教程" },
    { "Guide", "指南" }, { "FAQ", "常见问题" }, { "Terms", "条款" }, { "Privacy", "隐私" },
    { "License", "许可" }, { "Account", "账号" }, { "Login", "登录" }, { "Logout", "登出" },
    { "Register", "注册" }, { "Subscription", "订阅" }, { "Checkout", "结算" },
    { "Balance", "余额" }, { "Receive", "接收" }, { "Receive Only", "仅接收" },
    { "Send Only", "仅发送" }, { "Hide UI", "隐藏界面" }, { "Show UI", "显示界面" },
    { "Toggle Key", "开关按键" }, { "Binds", "绑定" }, { "Reset Key", "重置按键" },
    { "Default Key", "默认按键" },

    -- 方位 / 相对
    { "Left", "左侧" }, { "Right", "右侧" }, { "Up", "上" }, { "Down", "下" },
    { "Top", "顶部" }, { "Bottom", "底部" }, { "Center", "中心" }, { "Middle", "中间" },
    { "Front", "前方" }, { "Behind", "后方" }, { "Inside", "内部" }, { "Outside", "外部" },
    { "Nearby", "附近" }, { "Around", "周围" }, { "Under", "下方" }, { "Near", "近" },
    { "Far", "远" },

    -- 时间 / 频率
    { "Second", "秒" }, { "Minute", "分钟" }, { "Hour", "小时" }, { "Day", "天" },
    { "Week", "周" }, { "Month", "月" }, { "Year", "年" }, { "Today", "今天" },
    { "Tomorrow", "明天" }, { "Yesterday", "昨天" }, { "Morning", "早晨" },
    { "Evening", "晚间" }, { "Night", "夜晚" }, { "Every", "每" }, { "Per", "每" },
    { "Hourly", "每小时" }, { "Daily Reward", "每日奖励" }, { "Weekly Reward", "每周奖励" },

    -- 数量 / 修饰
    { "More", "更多" }, { "Less", "更少" }, { "Many", "许多" }, { "Some", "一些" },
    { "Each", "每个" }, { "Both", "两者" }, { "Most", "最多" }, { "Least", "最少" },
    { "Equal", "相等" }, { "Same", "相同" }, { "Different", "不同" }, { "Other", "其他" },
    { "Another", "另一个" }, { "Only", "仅" }, { "Also", "同时" }, { "Still", "仍然" },
    { "Sometimes", "有时" }, { "Usually", "通常" }, { "Rarely", "很少" }, { "Mostly", "大多" },

    -- 功能 / 反作弊
    { "Magic Bullet", "魔法子弹" }, { "Hitbox Expander", "判定框扩大" },
    { "Stream Proof", "防录制" }, { "Screenshot Proof", "防截图" }, { "Desync", "不同步" },
    { "Speed Hack", "加速" }, { "Fly Hack", "飞行" }, { "Anti-Gravity", "反重力" },
    { "Freeze", "冻结" }, { "Float", "漂浮" }, { "Spin", "旋转" }, { "Anti Report", "防举报" },
    { "Anti Crash", "防崩溃" }, { "Detector", "检测器" }, { "Detection", "检测" },
    { "Spectate", "观战" }, { "Executor", "执行器" }, { "Injector", "注入器" },
    { "Build Number", "版本号" }, { "Anti Stun", "防眩晕" }, { "Anti Ragdoll", "防布娃娃" },

    -- 常用整句 / 提示
    { "Reconnect Now", "立即重连" }, { "Reconnect", "重连" }, { "Rejoin on Disconnect", "断线时重进" },
    { "No charms to equip", "没有可装备的护符" }, { "No items to show", "没有可显示物品" },
    { "No data available", "暂无数据" }, { "No friends online", "没有在线好友" },
    { "No players found", "未找到玩家" }, { "No active feature", "暂无激活功能" },
    { "In use", "使用中" }, { "Not in use", "未使用" }, { "Not equipped", "未装备" },
    { "Not selected", "未选中" }, { "Not owned", "未拥有" }, { "Not unlocked", "未解锁" },
    { "Tap to open", "点击打开" }, { "Hold to open", "长按打开" }, { "Press to open", "按键打开" },
    { "Click to bind", "点击绑定" }, { "Press any key", "按任意键" }, { "Press the key", "按键绑定" },
    { "Right click to reset", "右键重置" }, { "Copied to clipboard", "已复制到剪贴板" },
    { "Saved successfully", "保存成功" }, { "Copied successfully", "复制成功" },
    { "Failed to load", "加载失败" }, { "Failed to save", "保存失败" },
    { "Are you sure", "确定吗" }, { "Please wait", "请稍候" }, { "This action cannot be undone", "此操作不可撤销" },
    { "Parries attacks right before they land; Spear and Dual Blades have no parry", "在攻击命中前格挡；长矛与双刃无法格挡" },
    { "Are you sure you want to continue", "确定要继续吗" },
    { "Use potion when below 30% HP", "生命低于 30% 时使用药水" },
    { "Fly to Waypoint", "飞行到传送点" }, { "Teleport to Player", "传送到玩家" },
    { "Teleport to Waypoint", "传送到传送点" }, { "Save Config for Next Session", "保存配置供下次使用" },
    { "Anti-Aim", "反自瞄" }, { "Anti-Aim Mode", "反自瞄模式" },
    { "Min Health to Heal", "治疗所需最低生命" }, { "Aim Smoothing Amount", "瞄准平滑幅度" },
    { "Auto Sell When Full", "背包满时自动出售" }, { "Unlock All Doors", "解锁所有门" },
    { "Click or press Delete to open", "点击或按 Delete 打开" },

    -- 专有名词直通（保证不会因为未翻译而整句被拒）
    { "Morvik", "Morvik" }, { "Roblox", "Roblox" }, { "Robux", "Robux" },
    { "Ancient Sands", "远古沙海" }, { "Super Charm", "超级护符" },
    { "Super Charm [Epic]", "超级护符 [史诗]" },
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
            if not ALLOW_LATIN[lw] then
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

local function translate(s)
    if type(s) ~= "string" or s == "" then return nil end
    if not s:find("[%a]") then return nil end            -- 纯数字/符号
    if s:find("[\228-\233]") then return nil end          -- 已含中文
    if s:find("http", 1, true) or s:find("www.", 1, true) then return nil end
    local cached = CACHE[s]
    if cached ~= nil then return cached or nil end
    local out, changed = {}, false
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
        local r, ch = translateSegment(line)
        out[#out + 1] = r
        changed = changed or ch
    end
    local res = nil
    if changed then res = table.concat(out, "\n") end
    if CACHE_N > 4000 then clearCache() end
    CACHE[s] = res or false
    CACHE_N += 1
    return res
end

----------------------------------------------------------------
-- 5. 应用到实例
----------------------------------------------------------------
local function isText(o)
    return o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")
end

local state = {
    enabled   = true,
    running   = false,
    originals = setmetatable({}, { __mode = "k" }),
    hooked    = setmetatable({}, { __mode = "k" }),
    busy      = setmetatable({}, { __mode = "k" }),
    conns     = {},
    count     = 0,
    guis      = 0,
}

local translateObj

local function watchObj(o)
    if state.hooked[o] then return end
    state.hooked[o] = true
    local c = o:GetPropertyChangedSignal("Text"):Connect(function()
        if state.enabled and state.running and not state.busy[o] then
            task.defer(translateObj, o)
        end
    end)
    table.insert(state.conns, c)
end

translateObj = function(o)
    if not state.enabled or not isText(o) then return end
    if state.busy[o] or o:GetAttribute("UIT_SELF") then return end

    local raw = o.Text
    if type(raw) == "string" and raw ~= "" then
        local new = translate(raw)
        if new and new ~= raw then
            state.originals[o] = raw
            state.busy[o] = true
            o.Text = new
            state.busy[o] = nil
            state.count += 1
            watchObj(o)
        end
    end

    if o:IsA("TextBox") then
        local ph = o.PlaceholderText
        if type(ph) == "string" and ph ~= "" then
            local newph = translate(ph)
            if newph and newph ~= ph then
                state.busy[o] = true
                o.PlaceholderText = newph
                state.busy[o] = nil
            end
        end
    end
end

local function restoreAll()
    local n = 0
    for inst, txt in pairs(state.originals) do
        if inst and inst.Parent then
            state.busy[inst] = true
            pcall(function() inst.Text = txt end)
            state.busy[inst] = nil
            n += 1
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
local MARKERS = {
    toggle = true, enabled = true, disabled = true, auto = true, esp = true,
    aimbot = true, speed = true, keybind = true, settings = true, config = true,
    player = true, players = true, teleport = true, farm = true, fps = true,
    ping = true, slot = true, amount = true, distance = true, radius = true,
    aim = true, silent = true, fly = true, noclip = true, godmode = true,
    delay = true, weapon = true, weapons = true, damage = true, health = true,
    team = true, enemy = true, target = true, notification = true, script = true,
    hub = true, feature = true, features = true, misc = true, visual = true,
    press = true, click = true, hold = true, value = true, range = true,
    luck = true, cooldown = true, upgrade = true, shop = true, quest = true,
}

local guiCache = setmetatable({}, { __mode = "k" })

local function textCount(gui)
    local n = 0
    local ok = pcall(function()
        for _, d in ipairs(gui:GetDescendants()) do
            if isText(d) then n += 1 end
        end
    end)
    return ok and n or 0
end

local function menuScore(gui)
    local score, seen = 0, {}
    pcall(function()
        for _, d in ipairs(gui:GetDescendants()) do
            if isText(d) then
                for w in tostring(d.Text):lower():gmatch("[%a]+") do
                    if MARKERS[w] and not seen[w] then
                        seen[w] = true
                        score += 1
                    end
                end
            end
        end
    end)
    return score
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
    return false
end

-- 判断某个 GUI（容器下的一级子项）是否为目标菜单
local function isTarget(gui)
    if not gui or not gui.Parent then return false end
    if gui:GetAttribute("UIT_SELF") then return false end
    local cached = guiCache[gui]
    if cached ~= nil then return cached end

    local ok, res = pcall(function()
        if nameExcluded(gui.Name) then return false end
        if nameIncluded(gui.Name) then
            if textCount(gui) >= 3 then return true end
        end
        local tc = textCount(gui)
        if tc < CONFIG.minTextsForMenu then return false end
        -- 文本量很大且不是 Roblox 自带界面，基本可以确定是脚本菜单
        if tc >= 80 then return true end
        return menuScore(gui) >= CONFIG.minMenuScore
    end)
    res = ok and res or false
    if res then
        guiCache[gui] = true
        state.guis += 1
    end
    return res
end

local function containerList()
    local list = {}
    local add = function(v)
        if typeof(v) == "Instance" then
            for _, x in ipairs(list) do if x == v then return end end
            table.insert(list, v)
        end
    end
    pcall(function() add(gethui and gethui()) end)
    pcall(function() add(get_hidden_gui and get_hidden_gui()) end)
    pcall(function() add(game:GetService("CoreGui")) end)
    if CONFIG.translatePlayerGui then
        pcall(function()
            local plr = game:GetService("Players").LocalPlayer
            add(plr and plr:FindFirstChildOfClass("PlayerGui"))
        end)
    end
    return list
end

-- 沿祖先链找最近的「菜单级」GUI
-- 只认 ScreenGui（脚本菜单基本都是 ScreenGui），Name 显式指定的容器才放宽
local function targetAncestor(o)
    local ok, res = pcall(function()
        local p = o.Parent
        while p do
            if guiCache[p] then return p end
            if p:IsA("ScreenGui") then
                if isTarget(p) then return p end
            elseif nameIncluded(p.Name) then
                guiCache[p] = true
                state.guis += 1
                return p
            end
            p = p.Parent
        end
        return nil
    end)
    if ok then return res end
    return nil
end

local function sweepContainer(c)
    local ok, desc = pcall(function() return c:GetDescendants() end)
    if not ok then return 0 end
    local n = 0
    for _, d in ipairs(desc) do
        if isText(d) then
            local okA, tgt = pcall(targetAncestor, d)
            if okA and tgt then
                local before = state.count
                pcall(watchObj, d)
                pcall(translateObj, d)
                if state.count > before then n += 1 end
            end
        end
    end
    return n
end

local function sweepAll()
    local n = 0
    for _, c in ipairs(containerList()) do
        local ok, r = pcall(sweepContainer, c)
        if ok then n += r end
    end
    return n
end

----------------------------------------------------------------
-- 7. 「中 / EN」浮动按钮
----------------------------------------------------------------
local toggleGui, toggleBtn

local function buildToggle()
    if not CONFIG.showToggle or toggleGui then return end
    local parent
    pcall(function() parent = gethui and gethui() end)
    if not parent then pcall(function() parent = game:GetService("CoreGui") end) end
    if not parent then return end

    toggleGui = Instance.new("ScreenGui")
    toggleGui.Name = "UIT_CN_Toggle"
    toggleGui.ResetOnSpawn = false
    toggleGui.IgnoreGuiInset = true
    toggleGui.DisplayOrder = 999999
    toggleGui:SetAttribute("UIT_SELF", true)

    toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "Toggle"
    toggleBtn:SetAttribute("UIT_SELF", true)
    toggleBtn.Size = UDim2.fromOffset(44, 28)
    toggleBtn.Position = UDim2.new(1, -60, 0, 160)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
    toggleBtn.BackgroundTransparency = 0.05
    toggleBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
    toggleBtn.TextSize = 14
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.Text = "中"
    toggleBtn.AutoButtonColor = true
    toggleBtn.Draggable = true
    toggleBtn.Parent = toggleGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = toggleBtn

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(72, 72, 80)
    stroke.Thickness = 1
    stroke.Parent = toggleBtn

    toggleBtn.MouseButton1Click:Connect(function()
        state.enabled = not state.enabled
        toggleBtn.Text = state.enabled and "中" or "EN"
        if state.enabled then sweepAll() else restoreAll() end
    end)

    toggleGui.Parent = parent
end

local function setEnabled(on)
    state.enabled = on
    if toggleBtn then toggleBtn.Text = on and "中" or "EN" end
    if on then sweepAll() else restoreAll() end
end

----------------------------------------------------------------
-- 8. 启动 / 停止 / 对外接口
----------------------------------------------------------------
local function start()
    buildToggle()
    sweepAll()

    if CONFIG.watchNewUI then
        for _, c in ipairs(containerList()) do
            local okConn, conn = pcall(function()
                return c.DescendantAdded:Connect(function(d)
                    if not state.enabled or not state.running then return end
                    task.defer(function()
                        if not state.enabled or not state.running then return end
                        if isText(d) then
                            local okA, tgt = pcall(targetAncestor, d)
                            if okA and tgt then
                                pcall(watchObj, d)
                                translateObj(d)
                            end
                        end
                    end)
                end)
            end)
            if okConn then table.insert(state.conns, conn) end
        end
    end

    task.spawn(function()
        local t0 = os.clock()
        while state.running and (os.clock() - t0) < CONFIG.rescanSeconds do
            task.wait(CONFIG.rescanInterval)
            if state.enabled and state.running then pcall(sweepAll) end
        end
    end)

    if CONFIG.verbose then
        local hubs = 0
        for _ in pairs(guiCache) do hubs += 1 end
        if hubs > 0 then
            print(("[UIT-CN] 已识别 %d 个界面，本次翻译 %d 个文本元素"):format(hubs, state.count))
        else
            print("[UIT-CN] 暂未发现脚本菜单，已进入监听：菜单打开后会自动翻译")
        end
    end
end

local api = {}
api.translate = translate
api.addPairs = addPairs
api.enable = function() setEnabled(true) end
api.disable = function() setEnabled(false) end
api.restore = function() return restoreAll() end
api.rescan = function() return sweepAll() end
api.stats = function() return state.count, state.guis, state.enabled end
api.stop = function()
    state.running = false
    for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
    state.conns = {}
    if toggleGui then pcall(function() toggleGui:Destroy() end) end
    toggleGui, toggleBtn = nil, nil
end

local prev = getgenv().UIT_CN
if type(prev) == "table" and type(prev.stop) == "function" then pcall(prev.stop) end
getgenv().UIT_CN = api

state.running = true
if CONFIG.autoApply then
    local ok, err = pcall(start)
    if not ok then warn("[UIT-CN] 启动失败: " .. tostring(err)) end
end
