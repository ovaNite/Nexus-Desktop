--[[
 NEXUS // v1.1 | AMMOBALANCED + HEALTH PICKUP IDENTIFICATION | ROBLOX / LUAU
 Source: newly designed from FLOWW v8.0, not a patch of its render/raycast engine.
 All information is CLIENT-VISIBLE ONLY. Missing opponent ammo/backpack shows "?".
 Shoot redirection / weapon edits require a compatible client-controlled game.
 ZERO workspace:Raycast, ZERO workspace:Spherecast, ZERO camera rewrites for Silent.
 RightShift: menu | End: emergency stop | Z: fly toggle
]]

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local HttpService = game:GetService('HttpService')
local CoreGui = game:GetService('CoreGui')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local LocalPlayer = Players.LocalPlayer
local env = (type(getgenv) == 'function' and getgenv()) or _G

-- Safely replace v8 and previous NEXUS runtime. Global hooks remain installed as a
-- passive forwarding bridge: reloading a Roblox process may be required for v7.9.
for _, stopName in ipairs({'NEXUS_STOP', 'FLOWW_STOP'}) do
    if type(env[stopName]) == 'function' then pcall(env[stopName]) end
end
local alive = true
local connections, owned, activeLights = {}, {}, {}
local function connect(signal, fn)
    local con = signal:Connect(fn)
    connections[#connections+1] = con
    return con
end
local function own(obj)
    owned[#owned+1] = obj
    return obj
end
local function safeDestroy(obj)
    if obj then pcall(function() obj:Destroy() end) end
end
local function clock() return os.clock() end
local function clamp(x,a,b) return math.clamp(x,a,b) end
local function ch() return LocalPlayer.Character end
local function rootOf(model)
    return model and (model:FindFirstChild('HumanoidRootPart') or model.PrimaryPart or model:FindFirstChildWhichIsA('BasePart'))
end
local function humanoidOf(model)
    return model and model:FindFirstChildOfClass('Humanoid')
end
local function aliveModel(model)
    local h = humanoidOf(model)
    return model and model.Parent and h and h.Health > 0 and rootOf(model) ~= nil
end
local function cam() return Workspace.CurrentCamera end
local function lower(s) return tostring(s or ''):lower() end
local function containsAny(s, arr)
    s = lower(s)
    for _, needle in ipairs(arr) do if s:find(needle,1,true) then return true end end
    return false
end
local function v3(x) return typeof(x) == 'Vector3' end

local Cfg = {
    Menu = true,
    ESP = true, ESPBox = true, ESPName = true, ESPHealth = true,
    ESPWeapon = true, ESPAmmo = true, ESPInventory = false,
    ESPHighlight = true, ESPRealLight = false, ESPMaxLight = 6,
    ESPDrops = true, ESPRange = 550, ESPMax = 20, ESPHz = 60, LootESPHz = 120, PreviewHz = 15,
    ModelPreview = true, ModelAutoRotate = true,
    TeamCheck = true, TargetNPCs = true, TargetRange = 500,
    AimEnabled = true, AimSmooth = 1, AimHardInput = true, AimFOV = 160,
    Silent = false, SilentFOV = 220, SilentGeneric = false,
    Trigger = false, TriggerCPS = 10, TriggerFOV = 14,
    ScanWeapons = true, ModuleConfigs = false, NoSpread = false, NoRecoil = false,
    FastFire = false, FastReload = false, AmmoAssist = false,
    AutoAmmo = true, AutoHeal = true, PickupRange = 500, PickupCooldown = 1,
    PickupAnywhere = true, LootMagnet = true, AdaptiveVisuals = true,
    Fly = false, FlySpeed = 90, ThirdPerson = false,
    Spin = false, SpinSpeed = 2,
    Debug = false,
}


-- ============================================================
-- SETTINGS: SAFE JSON AUTOSAVE (only when the runtime exposes file I/O)
-- The file uses a stable game-specific name across NEXUS releases.
-- With regular Roblox LocalScripts, writefile/readfile do not exist: fallback
-- preserves settings only across re-executions in the SAME client session.
-- ============================================================
local Settings = {
    path='NEXUS_settings_'..tostring(game.PlaceId)..'.json',
    backend='Sitzung', lastSave='noch nicht', dirty=false, lastChanged=0,
    lastWrite=0, writes=0, error=nil,
}
do
local settingsFileRead = type(readfile)=='function' and readfile
    or (type(env.readfile)=='function' and env.readfile or nil)
local settingsFileWrite = type(writefile)=='function' and writefile
    or (type(env.writefile)=='function' and env.writefile or nil)
local settingDefaults={}
for key,value in pairs(Cfg) do
    if type(value)=='boolean' or type(value)=='number' then
        if key~='Menu' then settingDefaults[key]=value end
    end
end
local settingBounds={
    ESPHz={30,240}, LootESPHz={30,240}, PreviewHz={10,60}, ESPMax={5,35}, ESPMaxLight={0,16},
    ESPRange={100,1200}, TargetRange={100,1500},
    PickupRange={3,500}, PickupCooldown={0.1,10},
    FlySpeed={20,200}, SpinSpeed={1,8},
    TriggerCPS={1,30}, TriggerFOV={1,100}, AimFOV={20,600},
    SilentFOV={20,600}, AimSmooth={1,30},
}
local function settingValue(key, value)
    local expected=settingDefaults[key]
    if expected==nil or type(value)~=type(expected) then return nil end
    if type(value)=='number' then
        if value~=value or value==math.huge or value==-math.huge then return nil end
        local bounds=settingBounds[key]
        if bounds then value=math.clamp(value,bounds[1],bounds[2]) end
        if key=='PickupCooldown' then
            return math.floor(value*10+0.5)/10
        end
        return math.floor(value+0.5)
    end
    return value
end
local function exportSettings()
    local values={}
    for key in pairs(settingDefaults) do values[key]=Cfg[key] end
    return values
end
local function importSettings(values)
    if type(values)~='table' then return false end
    for key,value in pairs(values) do
        local valid=settingValue(key,value)
        if valid~=nil then Cfg[key]=valid end
    end
    return true
end
local function loadSettings()
    local loaded=false
    if settingsFileRead then
        local ok, contents=pcall(settingsFileRead,Settings.path)
        if ok and type(contents)=='string' then
            local parsed, obj=pcall(function() return HttpService:JSONDecode(contents) end)
            if parsed and type(obj)=='table' and type(obj.values)=='table' then
                loaded=importSettings(obj.values)
                if loaded then Settings.backend='Datei' end
            end
        end
    end
    if not loaded and type(env.NEXUS_SESSION_SETTINGS)=='table' then
        loaded=importSettings(env.NEXUS_SESSION_SETTINGS)
    end
    if settingsFileWrite then
        Settings.backend=Settings.backend=='Datei' and 'Datei' or 'Datei (bereit)'
    end
end
function Settings.save(force)
    if not alive then return false end
    if not force and not Settings.dirty then return true end
    local values=exportSettings()
    env.NEXUS_SESSION_SETTINGS=values
    if settingsFileWrite then
        local encoded, json=pcall(function()
            return HttpService:JSONEncode({schema=1,values=values})
        end)
        if encoded then
            local ok, err=pcall(settingsFileWrite,Settings.path,json)
            if ok then
                Settings.backend='Datei';Settings.error=nil
                Settings.lastSave='gespeichert';Settings.lastWrite=clock()
                Settings.writes+=1;Settings.dirty=false
                return true
            end
            Settings.error=tostring(err)
        else Settings.error=tostring(json) end
    else Settings.error='Dateizugriff nicht vorhanden' end
    Settings.backend='Nur Sitzung'
    Settings.lastSave='nur Sitzung'
    Settings.dirty=false
    return false
end
function Settings.changed()
    Settings.dirty=true
    Settings.lastChanged=clock()
end
loadSettings()
end


-- HARD VISUAL BLOCK IN SPAWN/LOBBY. These points are from the original FLOWW
-- script for this experience. The block is unconditional, not a GUI toggle.
local V3 = {}
V3.KNOWN_LOBBY_SPAWNS = {
    Vector3.new(-119.644211, -677.249939, 1139.98853),
    Vector3.new(1449.4, -665.0, 1053.3),
}
V3.LOBBY_RADIUS = 525
V3.lobbyCheckAt, V3.lobbyCached = -10, true
function V3.inSpawnArea(worldPosition)
    if typeof(worldPosition)~='Vector3' then return false end
    for _,position in ipairs(V3.KNOWN_LOBBY_SPAWNS) do
        if (worldPosition-position).Magnitude <= V3.LOBBY_RADIUS then return true end
    end
    return false
end
function V3.inLobby()
    local now=clock()
    if now-V3.lobbyCheckAt < 0.08 then return V3.lobbyCached end
    V3.lobbyCheckAt=now
    local character=ch()
    local root=rootOf(character)
    if not root then V3.lobbyCached=true;return true end
    if V3.inSpawnArea(root.Position) then
        V3.lobbyCached=true;return true
    end
    for _,obj in ipairs({LocalPlayer,character,Workspace}) do
        if obj then
            for _,key in ipairs({'InLobby','IsInLobby','InSpawn','InSafeZone','SpawnProtected'}) do
                if obj:GetAttribute(key)==true then
                    V3.lobbyCached=true;return true
                end
            end
        end
    end
    local team=LocalPlayer.Team
    if team and containsAny(team.Name,{'lobby','spectator','waiting'}) then
        V3.lobbyCached=true;return true
    end
    V3.lobbyCached=false
    return false
end

local Palette = {
    bg = Color3.fromRGB(8,13,26), panel = Color3.fromRGB(12,20,38),
    pane2 = Color3.fromRGB(17,28,50), tile = Color3.fromRGB(19,34,58),
    tileHover = Color3.fromRGB(27,44,71), stroke = Color3.fromRGB(49,79,118),
    blue = Color3.fromRGB(49,150,255), cyan = Color3.fromRGB(57,238,255),
    tint = Color3.fromRGB(85,190,255), white = Color3.fromRGB(231,244,255),
    muted = Color3.fromRGB(132,163,191), green = Color3.fromRGB(65,235,169),
    red = Color3.fromRGB(255,95,124), amber = Color3.fromRGB(255,198,96),
}

local function log(...) if Cfg.Debug then print('[NEXUS]', ...) end end
local function element(class, parent, props)
    local e = Instance.new(class)
    for k,v in pairs(props or {}) do e[k] = v end
    e.Parent = parent
    return e
end
local function round(inst, rad)
    return element('UICorner', inst, {CornerRadius=UDim.new(0,rad or 10)})
end
local function stroke(inst, col, thick, alpha)
    return element('UIStroke',inst,{Color=col or Palette.stroke,Thickness=thick or 1,Transparency=alpha or 0})
end
local function gradient(inst, c1, c2, angle)
    return element('UIGradient', inst,{Rotation=angle or 0,
        Color=ColorSequence.new(c1,c2)})
end
local function label(parent,text,sz,color,bold)
    return element('TextLabel', parent,{
        BackgroundTransparency=1,Text=text,TextColor3=color or Palette.white,
        Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize=sz or 12,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,BorderSizePixel=0,
    })
end
local function tween(inst,props,duration)
    if alive and inst and inst.Parent then
        pcall(function() TweenService:Create(inst,TweenInfo.new(duration or 0.16,Enum.EasingStyle.Quad),props):Play() end)
    end
end

-- Only information actually replicated to the local machine can be inspected.
local WEAPON_HINTS = {'sniper','rifle','shotgun','smg','pistol','revolver','rocket',
    'rpg','crossbow','gun','weapon','blaster','ak-','m4','uzi','p90','mp5',
    'scar','famas','awp','deagle','railgun','minigun','laser','bow','grenade',
    'ak47','akm','glock','m16','m249','hk416','aug','galil','vss','svd','barrett',
    'handgun','firearm','carbine','musket','flintlock','leveraction','lmg','dmr',
    'handcannon','sidearm','assault','marksman','burst','machinegun','flamethrower',
    'scope','tactical','repeater','snub','magnum','mk18','vector','kar98','m1garand',
    'model_ak','laserbeam','katana','sword','combatknife','crossbow','railrifle'}
local AMMO_KEYS = {'ammo','bullets','magazine','clip','rounds','reserve','mag','currentammo'}
local HP_KEYS = {'medkit','health','healing','heal','bandage','first aid','medical','medic','firstaid','stim','medbag','healthpack'}
local AMMO_LOOT_KEYS = {'ammo','ammunition','bullets','magazine','rounds','cartridge','ammopack','supplybox','resupply','munitions'}
local LOOT_CONTAINER_KEYS = {'drop','pickup','loot','item','collect','worlditem','supply'}
local SHOT_KEYS = {
    direction=true,bulletdirection=true,aimdirection=true,shotdirection=true,
    hitposition=true,hitpos=true,mouseposition=true,mousehit=true,
    targetposition=true,targetpos=true,endpoint=true,bulletend=true,
    projectileend=true,shootdirection=true,fireposition=true,
}
local ORIGIN_KEYS = {'origin','start','muzzle','from','source','startposition'}
local SHOT_REMOTE_WORDS = {'fire','shoot','shot','bullet','projectile','registerhit','hitreg'}
local GENERIC_REMOTE_WORDS = {'functions','replicate','net','network'}
local STATS_KEYS = {
    spread = {'spread','bloom','accuracycone','bulletspread','hipspread','aimcone','spraycone','shotcone','bulletdeviation','inaccuracy','maxbloom','minbloom','spreadangle','spreadmultiplier','hipfirespread','adsaccuracy'},
    recoil = {'recoil','kick','camerashake','weaponkick','viewkick','camerakick','gunshake','verticalkick','horizontalkick'},
    firerate = {'cooldown','delaybetweenshots','shotdelay','fireinterval','shotinterval','firerateinterval','rateoffire','shootdelay', 'firerate','rpm','roundsperminute','roundspersecond','shotspersecond','firespeed','shotcooldown','firecooldown'},
    reload = {'reloadtime','reloadduration','reloadspeed','reloadinterval'},
    ammo = {'currentammo','ammo','magazine','reserveammo','bullets','clipammo','ammoleft','magammo','bulletcount','ammocount'},
}
local function keyType(name)
    local n = lower(name):gsub('[^a-z0-9]','')
    for typ, arr in pairs(STATS_KEYS) do
        for _,word in ipairs(arr) do if n == word or n:find(word,1,true) then return typ end end
    end
    return nil
end
local function statEnabled(k)
    return (k == 'spread' and Cfg.NoSpread)
        or (k == 'recoil' and Cfg.NoRecoil)
        or (k == 'firerate' and Cfg.FastFire)
        or (k == 'reload' and Cfg.FastReload)
        or (k == 'ammo' and Cfg.AmmoAssist)
end
-- Some games store rate as shots/sec or RPM; others store seconds per shot.
-- Reducing an RPM or shots/sec value makes the weapon SLOWER, not faster.
local function statNumber(kind,original,field)
    if kind == 'spread' or kind == 'recoil' then return 0 end
    local key=lower(field):gsub('[^a-z0-9]','')
    if kind == 'firerate' then
        if key:find('rpm',1,true) or key:find('roundsperminute',1,true) then
            return math.min(1200,math.max(0,original)*2)
        end
        if key=='firerate' or key=='rateoffire' or key:find('persecond',1,true)
            or key=='firespeed' then
            return math.min(40,math.max(0,original)*2)
        end
        return math.max(0.025,math.max(0,original)*0.35)
    end
    if kind == 'reload' then return math.max(0.1, original * 0.25) end
    if kind == 'ammo' then return math.max(9999, original) end
    return original
end

-- Weapon metadata from other players is often NOT replicated. Unknown stays unknown.
local function scanNumber(obj,names)
    if not obj then return nil end
    local rank={}
    for i,key in ipairs(names) do
        rank[lower(key):gsub('[^a-z0-9]','')]=i
    end
    local bestRank,bestValue=math.huge,nil
    local function candidate(key,value,depth)
        if type(value)~='number' or value~=value then return end
        local normalized=lower(key):gsub('[^a-z0-9]','')
        local priority=rank[normalized]
        if not priority then
            for name,i in pairs(rank) do
                if normalized:find(name,1,true) then
                    priority=math.min(priority or math.huge,70+i)
                end
            end
        end
        if priority then
            local score=priority*10+depth
            if score<bestRank then bestRank=score;bestValue=value end
        end
    end
    local function inspect(node,depth)
        local attrs=node:GetAttributes()
        for key,value in pairs(attrs) do candidate(key,value,depth) end
        if node:IsA('NumberValue') or node:IsA('IntValue') then
            candidate(node.Name,node.Value,depth)
        end
    end
    inspect(obj,0)
    local checked=0
    for _,d in ipairs(obj:GetDescendants()) do
        checked+=1
        if checked>280 then break end
        if d:IsA('NumberValue') or d:IsA('IntValue') or d:IsA('Configuration')
            or d:IsA('Folder') or d:IsA('Model') or d:IsA('Tool') then
            inspect(d,2)
        end
    end
    return bestValue~=nil and math.floor(bestValue) or nil
end
-- Prefer truly equipped Tools. Fall back to named viewmodels/active equipment
-- only when the local client actually has such Instances.
local WEAPON_CLASS_KEYS={'WeaponClass','WeaponType','WeaponName','GunName','EquippedWeapon','CurrentWeapon','HeldWeapon','CurrentGun','EquippedItem','ActiveWeapon','SelectedWeapon','ItemName','WeaponId','GunId','Gun','Weapon','ActiveGun','EquippedGun','PrimaryWeapon','SecondaryWeapon','Holding','HeldItem'}

-- v0.7: Score real character-attached weapon objects, not generic body parts.
-- Work is bounded: no unrestricted workspace GetDescendants() every frame.
V3.WEAPON_SOCKET_HINTS={'muzzle','barrel','firepoint','shootpoint','gunpoint','bulletorigin','aimpoint'}
V3.WEAPON_CONTAINER_HINTS={'equipped','held','weapons','guns','equipment','loadout','viewmodel','thirdperson','weaponmodel'}
function V3.weaponEvidence(obj)
    if not obj or not (obj:IsA('Tool') or obj:IsA('Model') or obj:IsA('BasePart')) then return -999 end
    if obj:IsA('Accessory') or obj:IsA('Humanoid') then return -999 end
    if obj:IsA('Model') and humanoidOf(obj) then return -999 end
    if obj:IsA('BasePart') and containsAny(obj.Name,{'head','torso','arm','hand','leg','foot','humanoidrootpart','handle'})
        and not containsAny(obj.Name,WEAPON_HINTS) then return -999 end
    local score=obj:IsA('Tool') and 190 or obj:IsA('Model') and 15 or 0
    local n=lower(obj.Name)
    if containsAny(n,WEAPON_HINTS) then score+=105 end
    if containsAny(n,{'equippedgun','heldgun','primarygun','currentweapon','weaponmodel'}) then score+=75 end
    local par=obj.Parent
    if par and containsAny(par.Name,V3.WEAPON_CONTAINER_HINTS) then score+=55 end
    -- Most descendants of an R15 rig are generic body parts. Do not probe
    -- dozens of attributes on each of them at every enemy-info refresh.
    if obj:IsA('BasePart') and score<50 then return -999 end
    if obj:GetAttribute('Equipped')==true or obj:GetAttribute('IsEquipped')==true
        or obj:GetAttribute('Active')==true or obj:GetAttribute('IsActive')==true then score+=75 end
    for _,key in ipairs(WEAPON_CLASS_KEYS) do
        local v=obj:GetAttribute(key)
        if (type(v)=='string' and #v>1) or typeof(v)=='Instance' then
            score+=95; break
        end
    end
    -- Detect generic named guns by their explicit shooting attachment, without
    -- misclassifying every arm/body mesh as a weapon.
    if obj:IsA('Model') or obj:IsA('Tool') then
        local q={obj};local i,nodes=1,0
        while i<=#q and nodes<24 do
            local node=q[i];i+=1;nodes+=1
            for _,c in ipairs(node:GetChildren()) do
                if containsAny(c.Name,V3.WEAPON_SOCKET_HINTS) then score+=85;return score end
                if c:IsA('Model') or c:IsA('Folder') then q[#q+1]=c end
            end
        end
    end
    return score
end
function V3.linkedExternalWeapon(obj,character,player)
    if not obj or not character or not player then return false end
    local ids={player.Name,character.Name,tostring(player.UserId)}
    for _,key in ipairs({'OwnerUserId','UserId','EquippedByUserId','PlayerUserId','Owner','CharacterName','PlayerName','EquippedBy'}) do
        local v=obj:GetAttribute(key)
        if type(v)=='number' and v==player.UserId then return true end
        if type(v)=='string' then
            for _,id in ipairs(ids) do if lower(v)==lower(id) then return true end end
        end
    end
    for _,c in ipairs(obj:GetChildren()) do
        if c:IsA('ObjectValue') and containsAny(c.Name,{'owner','holder','player','character','wielder','equipped'})
            and (c.Value==character or c.Value==player) then return true end
    end
    -- A weapon can be stored as Workspace.WeaponModels.PlayerName.Gun.
    local p=obj
    for _=1,3 do
        if not p or p==Workspace then break end
        if lower(p.Name)==lower(player.Name) or lower(p.Name)==lower(character.Name) then return true end
        p=p.Parent
    end
    return false
end
local function weaponFromModel(model)
    if not model then return nil end
    local selected,best=nil,88
    local function consider(obj,depth,boost)
        local score=V3.weaponEvidence(obj)-(depth or 0)*3+(boost or 0)
        if score>best then best=score;selected=obj end
    end
    local queue={{node=model,depth=-1}}
    local qi,seen=1,0
    while qi<=#queue and seen<480 do
        local item=queue[qi];qi+=1
        for _,obj in ipairs(item.node:GetChildren()) do
            seen+=1
            if seen>480 then break end
            local depth=item.depth+1
            consider(obj,depth)
            if depth<8 and (obj:IsA('Model') or obj:IsA('Folder') or
                obj:IsA('Accessory') or obj:IsA('Tool')) then
                queue[#queue+1]={node=obj,depth=depth}
            end
        end
    end
    if model==ch() then
        local c=cam()
        if c then
            local count=0
            for _,obj in ipairs(c:GetChildren()) do
                count+=1; if count>90 then break end
                -- The active FPS model can be named directly after the weapon,
                -- e.g. 'Sniper', rather than 'ViewModel' or 'Weapon'.
                if obj:IsA('Model') or obj:IsA('Tool') or obj:IsA('Folder') then
                    consider(obj,1)
                    for _,child in ipairs(obj:GetChildren()) do
                        consider(child,2)
                        if child:IsA('Model') then
                            for _,sub in ipairs(child:GetChildren()) do consider(sub,3) end
                        end
                    end
                end
            end
        end
    else
        -- Some games replicate third-person guns in separate named world folders.
        -- Only accept an explicit owner link. Never guess a nearby gun belongs
        -- to a player merely because it is spatially close.
        local player=Players:GetPlayerFromCharacter(model)
        if player then
            local checked=0
            for _,folder in ipairs(Workspace:GetChildren()) do
                if checked>=8 then break end
                if (folder:IsA('Folder') or folder:IsA('Model')) and
                    containsAny(folder.Name,{'weaponmodels','equippedweapons','playerweapons','heldweapons','thirdpersonweapons','weapons','guns','viewmodels'}) then
                    checked+=1
                    local num=0
                    for _,node in ipairs(folder:GetChildren()) do
                        num+=1; if num>95 then break end
                        if V3.linkedExternalWeapon(node,model,player) then
                            consider(node,1,75)
                            for _,child in ipairs(node:GetChildren()) do consider(child,2,75) end
                        end
                    end
                end
            end
        end
    end
    return selected
end
V3.equippedLabelKeys={
    'EquippedWeapon','CurrentWeapon','HeldWeapon','ActiveWeapon','SelectedWeapon',
    'WeaponName','GunName','CurrentGun','EquippedItem','ItemName','WeaponId','GunId',
    'EquippedGun','ActiveGun','PrimaryWeapon','SecondaryWeapon','HeldItem','Weapon','Gun',
    'SelectedGun','SelectedWeaponName','CurrentWeaponName','EquippedWeaponName',
    'ActiveItem','CurrentItem','SelectedItem','Primary','Secondary','CurrentSlotWeapon',
    'LoadoutWeapon','HoldingWeapon','WeaponIdentifier','GunType','WeaponTypeName',
    'SelectedWeaponId','WeaponAsset','EquippedAsset','ItemEquipped',
}
function V3.readEquippedLabel(obj)
    if not obj then return nil,nil end
    local valid={}
    for _,key in ipairs(V3.equippedLabelKeys) do
        valid[lower(key):gsub('[^%w]','')]=true
    end
    local function nonempty(value)
        if type(value)=='string' and #value>1 and #value<95 then return value end
        if typeof(value)=='Instance' and value.Parent then return value.Name end
        return nil
    end
    for _,key in ipairs(V3.equippedLabelKeys) do
        local v=nonempty(obj:GetAttribute(key))
        if v then return v,'Attr:'..key end
        local child=obj:FindFirstChild(key)
        if child and child:IsA('StringValue') then
            v=nonempty(child.Value)
        elseif child and child:IsA('ObjectValue') then
            v=nonempty(child.Value)
        end
        if v then return v,'Value:'..key end
    end
    -- Some games use weapon_name, current_gun, or mixed-case keys.
    for key,value in pairs(obj:GetAttributes()) do
        if valid[lower(key):gsub('[^%w]','')] then
            local v=nonempty(value)
            if v then return v,'Attr:'..key end
        end
    end
    local n=0
    for _,child in ipairs(obj:GetChildren()) do
        n+=1;if n>50 then break end
        if valid[lower(child.Name):gsub('[^%w]','')] then
            local value=child:IsA('StringValue') and child.Value
                or (child:IsA('ObjectValue') and child.Value or nil)
            local v=nonempty(value)
            if v then return v,'Value:'..child.Name end
        end
    end
    return nil,nil
end
-- v0.7: Many games keep the equipped weapon as a Value/attribute in a
-- replicated Inventory/Combat/Loadout tree, not as a Tool under Character.
-- Walk only shallow, bounded, character-/player-owned data; never invent a
-- weapon from ReplicatedStorage's generic asset catalogue.
V3.WEAPON_FIELD_MARKERS={'weapon','gun','firearm','equipped','holding','held','selected','activeitem',
    'currentitem','currentgun','currentweapon','primary','secondary','loadoutslot','itemid','slotweapon'}
V3.WEAPON_CONTAINER_MARKERS={'weapon','gun','combat','equipment','inventory','loadout',
    'hotbar','playerdata','data','items','held','equipped','selected','active','slot'}
function V3.readWeaponTree(model,player)
    local bestName,bestSource,bestScore=nil,nil,0
    local roots={model,player}
    local function consider(value,source,score)
        if typeof(value)=='Instance' then
            if not value.Parent then return end
            value=value.Name
        end
        if type(value)~='string' then return end
        local str=value:match('^%s*(.-)%s*$')
        if #str<2 or #str>90 or tonumber(str) or containsAny(str,{'nil','none','unequipped','unknown','placeholder'}) then return end
        if score>bestScore then
            bestName,bestSource,bestScore=str,source,score
        end
    end
    for _,sourceRoot in ipairs(roots) do
        if sourceRoot then
            local q={{obj=sourceRoot,depth=0,context=false}}
            local i,inspected=1,0
            while i<=#q and inspected<260 do
                local item=q[i];i+=1;inspected+=1
                local node=item.obj
                local attributes=node:GetAttributes()
                for key,value in pairs(attributes) do
                    local isField=containsAny(key,V3.WEAPON_FIELD_MARKERS)
                    if isField then
                        consider(value,node.Name..'/@'..key,item.context and 145 or 110)
                    elseif item.context and containsAny(node.Name,{'equipped','currentweapon','currentgun','selectedweapon'})
                        and containsAny(key,{'name','type','id','item'}) then
                        consider(value,node.Name..'/@'..key,65)
                    end
                end
                local context=item.context or containsAny(node.Name,V3.WEAPON_CONTAINER_MARKERS)
                if node:IsA('StringValue') or node:IsA('ObjectValue') then
                    local isField=containsAny(node.Name,V3.WEAPON_FIELD_MARKERS)
                    if isField or context then
                        consider(node.Value,node.Name..'/Value',isField and 160 or 65)
                    end
                end
                if item.depth<4 then
                    for _,child in ipairs(node:GetChildren()) do
                        if child:IsA('Folder') or child:IsA('Configuration') or
                            child:IsA('Model') or child:IsA('ObjectValue') or
                            child:IsA('StringValue') or child:IsA('Tool') then
                            -- Character rigs contain many unrelated model/mesh objects.
                            if item.depth==0 or context or containsAny(child.Name,V3.WEAPON_CONTAINER_MARKERS)
                                or child:IsA('StringValue') or child:IsA('ObjectValue') or child:IsA('Tool') then
                                q[#q+1]={obj=child,depth=item.depth+1,context=context}
                            end
                        end
                    end
                end
            end
        end
    end
    return bestName,bestSource
end

-- Player-specific replicated data may live outside the character tree.
-- Only search folders explicitly named after this player/user ID.
function V3.readSharedPlayerWeapon(player)
    if not player then return nil,nil end
    local keys={player.Name,tostring(player.UserId)}
    local parents={Workspace,ReplicatedStorage}
    local folders={'PlayerData','Players','PlayerStats','Profiles','Characters',
        'PlayerInformation','UserData','Loadouts','Equipment','WeaponData'}
    for _,parent in ipairs(parents) do
        for _,folderName in ipairs(folders) do
            local holder=parent:FindFirstChild(folderName)
            if holder then
                for _,key in ipairs(keys) do
                    local ownedFolder=holder:FindFirstChild(key)
                    if ownedFolder then
                        local value,path=V3.readWeaponTree(ownedFolder,nil)
                        if value then
                            return value,parent.Name..'/'..holder.Name..'/'..key..'/'..path
                        end
                    end
                end
            end
        end
    end
    return nil,nil
end
-- v0.9: READ-ONLY replicated enemy loadout snapshot. Never scans the entire
-- Workspace or ReplicatedStorage. Never invokes other players' modules/remotes.
-- A server-only Backpack, hidden inventory, or locally rendered first-person
-- weapon cannot be recovered from another client's replicated state.
V3.enemyLoadoutCache=setmetatable({}, {__mode='k'})
V3.LOADOUT_ROOT_NAMES={'PlayerData','Players','PlayerStats','Profiles','Characters',
    'PlayerInformation','UserData','Loadouts','Equipment','WeaponData','Inventories',
    'Inventory','PlayerInventories','Data','CharacterData','PlayerProfiles','Sessions'}
V3.INVENTORY_CONTAINERS={'inventory','backpack','loadout','equipment','hotbar','items',
    'weapons','ownedweapons','primary','secondary','slots','storage','gear'}
V3.EQUIPPED_KEYS={'equippedweapon','currentweapon','activeweapon','heldweapon',
    'selectedweapon','equippedgun','currentgun','selectedgun','activegun',
    'holdingweapon','weaponname','gunname','activeitem','helditem','equippeditem',
    'currentitem','weaponequipped','itemequipped','currentweaponid','currentgunid'}
V3.INVENTORY_KEYS={'inventory','backpack','loadout','ownedweapons','items',
    'weapons','equipment','hotbar','itemlist','loadoutdata','gear'}
function V3.readEnemyLoadout(model, player, force)
    if not model or not model.Parent then
        return {weapon=nil,inventory='Keine replizierten Daten',items={},sources={},roots=0,nodes=0}
    end
    local last=V3.enemyLoadoutCache[model]
    if not force and last and clock()-last.time<3 then return last end
    local found={weapon=nil,weaponSource=nil,weaponScore=0,weaponObject=nil,
        items={},sources={},roots=0,nodes=0,time=clock()}
    local seenItems={}
    local roots,rootSeen={},{}
    local function addRoot(obj,desc)
        if not obj or rootSeen[obj] then return end
        rootSeen[obj]=true; roots[#roots+1]={node=obj,label=desc};
    end
    addRoot(model,'Character')
    if player then
        addRoot(player,'Player')
        local bp=player:FindFirstChildOfClass('Backpack') or player:FindFirstChild('Backpack')
        if bp then addRoot(bp,'Backpack (repliziert)') end
        -- Ownership is proven by the EXACT username/UserId folder, not proximity.
        for _,service in ipairs({Workspace,ReplicatedStorage}) do
            for _,holderName in ipairs(V3.LOADOUT_ROOT_NAMES) do
                local holder=service:FindFirstChild(holderName)
                if holder then
                    for _,id in ipairs({player.Name,tostring(player.UserId)}) do
                        local specific=holder:FindFirstChild(id)
                        if specific then addRoot(specific,service.Name..'/'..holderName..'/'..id) end
                    end
                end
            end
        end
    end
    local function normalize(v)
        if typeof(v)=='Instance' then
            if not v.Parent then return nil end
            return v.Name
        end
        if type(v)~='string' then return nil end
        local s=v:match('^%s*(.-)%s*$')
        if #s<2 or #s>100 or tonumber(s) or lower(s)=='nil' or
            containsAny(lower(s),{'unknown','unequipped','placeholder','not equipped'}) then return nil end
        return s
    end
    local function addItem(v,path)
        local s=normalize(v)
        if not s or containsAny(s,{'http://','https://','rbxasset','rbxthumb','<font','<img'}) then return end
        if containsAny(s,{'humanoidrootpart','leftarm','rightarm','leftleg','rightleg','torso','headattachment'}) then return end
        if #found.items>=18 then return end
        local key=lower(s)
        if not seenItems[key] then
            seenItems[key]=true;found.items[#found.items+1]=s
            found.sources[#found.sources+1]=path
        end
    end
    local function equipped(v,path,score,obj)
        local s=normalize(v)
        if not s then return end
        if score>found.weaponScore then
            found.weapon=s;found.weaponSource=path;found.weaponScore=score
            if obj and (obj:IsA('Tool') or obj:IsA('Model') or obj:IsA('Accessory')) then
                found.weaponObject=obj
            end
        end
    end
    -- Many replicated games store loadouts as JSON string attributes/values.
    -- Parse bounded strings only, never execute code and never treat generic
    -- inventory entries as the currently equipped gun.
    local jsonCount=0
    local function parseInventoryJSON(value,path)
        if type(value)~='string' or #value>3500 or jsonCount>=5 then return end
        local first=value:sub(1,1)
        if first~='[' and first~='{' then return end
        jsonCount+=1
        local ok,obj=pcall(function() return HttpService:JSONDecode(value) end)
        if not ok or type(obj)~='table' then return end
        local q={{t=obj,d=0}};local qi=1
        while qi<=#q and qi<=55 do
            local entry=q[qi];qi+=1
            for k,v in pairs(entry.t) do
                local key=lower(k):gsub('[^%w]','')
                if type(v)=='table' and entry.d<2 then
                    q[#q+1]={t=v,d=entry.d+1}
                elseif type(v)=='string' then
                    if containsAny(key,V3.EQUIPPED_KEYS) then equipped(v,path..'/'..tostring(k),210) end
                    if containsAny(key,{'name','item','weapon','gun','slot','id','type'}) then addItem(v,path..'/'..tostring(k)) end
                    if type(k)=='number' then addItem(v,path..'/'..tostring(k)) end
                end
            end
        end
    end
    for _,rootRec in ipairs(roots) do
        if found.nodes>=480 then break end
        found.roots+=1
        local q={{node=rootRec.node,d=0,inv=false}};local qi=1
        while qi<=#q and found.nodes<480 do
            local entry=q[qi];qi+=1
            found.nodes+=1
            local node=entry.node
            local name=lower(node.Name)
            local key=name:gsub('[^%w]','')
            local inv=entry.inv or containsAny(name,V3.INVENTORY_CONTAINERS)
            local path=rootRec.label..'/'..node.Name
            if node~=model and node:IsA('Tool') then
                local label=select(1,V3.readEquippedLabel(node)) or node.Name
                addItem(label,path)
                if node:IsDescendantOf(model) then
                    equipped(label,path..' [equipped Tool]',350,node)
                end
            elseif node~=model and node:IsA('Accessory') then
                if node:IsDescendantOf(model) and containsAny(name,WEAPON_HINTS) then
                    equipped(node.Name,path..' [weapon Accessory]',220,node)
                end
            elseif node~=model and node:IsA('Model') and node:IsDescendantOf(model)
                and not humanoidOf(node) and containsAny(name,WEAPON_HINTS) then
                equipped(node.Name,path..' [weapon model]',245,node)
            end
            -- A child named WeaponName/CurrentGun may be a StringValue or ObjectValue.
            if node:IsA('StringValue') or node:IsA('ObjectValue') then
                local v=node.Value
                if containsAny(key,V3.EQUIPPED_KEYS) then equipped(v,path..'/Value',310) end
                if inv then
                    if node:IsA('StringValue') then
                        addItem(v,path)
                        if containsAny(name,V3.INVENTORY_KEYS) then parseInventoryJSON(v,path) end
                    elseif typeof(v)=='Instance' then addItem(v,path) end
                end
            elseif node:IsA('IntValue') or node:IsA('NumberValue') then
                -- Weapon ID is not a name; do not hallucinate a matching asset.
            elseif inv and node~=rootRec.node and node:IsA('Folder') and
                (containsAny(name,WEAPON_HINTS) or node:GetAttribute('ItemName')) then
                addItem(node:GetAttribute('ItemName') or node.Name,path)
            end
            local attrs=node:GetAttributes()
            for k,v in pairs(attrs) do
                local ak=lower(k):gsub('[^%w]','')
                if containsAny(ak,V3.EQUIPPED_KEYS) then
                    equipped(v,path..'/@'..tostring(k),300)
                elseif containsAny(ak,V3.INVENTORY_KEYS) then
                    if type(v)=='string' then
                        parseInventoryJSON(v,path..'/@'..tostring(k))
                        if v:sub(1,1)~='[' and v:sub(1,1)~='{' then
                            for item in v:gmatch('[^,;|]+') do addItem(item,path..'/@'..tostring(k)) end
                        end
                    end
                elseif inv and containsAny(ak,{'itemname','weaponname','displayname','gunname','slotname'}) then
                    addItem(v,path..'/@'..tostring(k))
                end
            end
            if entry.d<5 then
                for _,child in ipairs(node:GetChildren()) do
                    if child:IsA('Folder') or child:IsA('Configuration') or
                       child:IsA('Model') or child:IsA('Tool') or child:IsA('Accessory') or
                       child:IsA('StringValue') or child:IsA('ObjectValue') or
                       child:IsA('NumberValue') or child:IsA('IntValue') then
                        local childContext=inv or containsAny(child.Name,V3.INVENTORY_CONTAINERS)
                        -- Skip unrelated rig branches and large avatar cosmetic trees.
                        if entry.d<=1 or childContext or
                            containsAny(child.Name,V3.WEAPON_FIELD_MARKERS) or
                            child:IsA('Tool') then
                            q[#q+1]={node=child,d=entry.d+1,inv=childContext}
                        end
                    end
                end
            end
        end
    end
    found.inventory=#found.items>0 and table.concat(found.items,', '):sub(1,240)
        or 'Keine replizierten Inventardaten'
    V3.enemyLoadoutCache[model]=found
    return found
end

V3.weaponReadCache=setmetatable({}, {__mode='k'})
local function getWeaponInfo(model)
    if not model then return nil,'Unbekannt',nil,nil,'no-model' end
    local cached=V3.weaponReadCache[model]
    if cached and clock()-cached.time<(cached.name=='Nicht repliziert' and 0.85 or 1.5) then
        return cached.tool,cached.name,cached.ammo,cached.reserve,cached.source
    end
    local player=Players:GetPlayerFromCharacter(model)
    local tool=weaponFromModel(model)
    local name,source=nil,'nicht repliziert'
    if tool then
        name,source=V3.readEquippedLabel(tool)
        if not name and (tool:IsA('Tool') or containsAny(tool.Name,WEAPON_HINTS)) then
            name=tool.Name;source='3D-Objekt:'..tool.ClassName
        end
    end
    -- Even if the 3D weapon object is absent, many games replicate an equipped
    -- weapon name on the Character, Player, or an Equipment/WeaponData folder.
    if not name then
        for _,obj in ipairs({model,player}) do
            if obj then
                local value,where=V3.readEquippedLabel(obj)
                if value then name=value;source=obj.ClassName..'/'..where;break end
            end
        end
    end
    if not name then
        for _,parent in ipairs({model,player}) do
            if parent then
                local containers=0
                for _,child in ipairs(parent:GetChildren()) do
                    if containsAny(child.Name,{'equipment','loadout','weapon','inventory','combat','gun','active','holder','primary'}) then
                        containers+=1
                        local value,where=V3.readEquippedLabel(child)
                        if value then name=value;source=child.Name..'/'..where;break end
                        for _,sub in ipairs(child:GetChildren()) do
                            if (sub:IsA('StringValue') or sub:IsA('ObjectValue')) and
                                containsAny(sub.Name,{'equipped','current','active','held','weapon','gun'}) then
                                local sv=sub:IsA('StringValue') and sub.Value or (sub.Value and sub.Value.Name)
                                if type(sv)=='string' and #sv>0 then name=sv;source=sub.Name;break end
                            end
                        end
                    end
                    if name or containers>=12 then break end
                end
                if name then break end
            end
        end
    end
    -- v0.9: actual linked equipped-weapon observation, not just inventory text.
    local observed=V3.readEnemyLoadout(model,player)
    if observed.weapon and (not name or observed.weaponScore>=300) then
        name=observed.weapon
        source=observed.weaponSource or 'Replicated loadout'
        if not tool and observed.weaponObject then tool=observed.weaponObject end
    end
    if not name then
        local discovered,where=V3.readWeaponTree(model,player)
        if discovered then name=discovered;source='Replicated:'..where end
    end
    if not name then
        local discovered,where=V3.readSharedPlayerWeapon(player)
        if discovered then name=discovered;source='PlayerData:'..where end
    end
    if not name and tool then name=tool.Name;source='Modell (unklar):'..tool.ClassName end
    -- When the game does not replicate any equipped weapon data, there is
    -- nothing reliable to identify: avoid displaying a guessed gun name.
    name=name or 'Nicht repliziert'
    local ammo=tool and scanNumber(tool,{'CurrentAmmo','MagAmmo','MagazineAmmo','AmmoInMag','Ammo','Magazine','Clip','Bullets','RoundsLeft'}) or nil
    local reserve=tool and scanNumber(tool,{'ReserveAmmo','BackupAmmo','TotalAmmo','SpareAmmo','AmmoReserve'}) or nil
    -- Only public numeric fields; never infer missing opponent ammo values.
    if ammo==nil then ammo=scanNumber(model,{'CurrentAmmo','MagAmmo','MagazineAmmo','AmmoInMag','Ammo','RoundsLeft'}) end
    if reserve==nil then reserve=scanNumber(model,{'ReserveAmmo','BackupAmmo','SpareAmmo','AmmoReserve'}) end
    V3.weaponReadCache[model]={time=clock(),tool=tool,name=name,ammo=ammo,reserve=reserve,source=source}
    return tool,name,ammo,reserve,source
end

local function getVisibleInventory(model)
    if not model or not model.Parent then return 'Keine replizierten Inventardaten' end
    local player=Players:GetPlayerFromCharacter(model)
    return V3.readEnemyLoadout(model,player).inventory
end

-- Reversible weapon stat editing: only local accessible tool values and attributes.
local savedValues = setmetatable({}, {__mode='k'})
local savedAttrs = setmetatable({}, {__mode='k'})
local savedTables = setmetatable({}, {__mode='k'})
local loadedModules = setmetatable({}, {__mode='k'})
local loadingModules = setmetatable({}, {__mode='k'})
local function patchConfigTable(tbl, depth, seen, count)
    if type(tbl)~='table' or depth>3 or seen[tbl] or count.n>240 then return end
    seen[tbl]=true
    for key,value in pairs(tbl) do
        count.n+=1
        if count.n>240 then break end
        local kind=keyType(key)
        if type(value)=='number' and kind and statEnabled(kind) then
            if not savedTables[tbl] then savedTables[tbl]={} end
            if savedTables[tbl][key]==nil then savedTables[tbl][key]=value end
            pcall(function() tbl[key]=statNumber(kind,savedTables[tbl][key],key) end)
        elseif type(value)=='table' then
            patchConfigTable(value,depth+1,seen,count)
        end
    end
end
local function restoreConfigTables()
    for tbl,entries in pairs(savedTables) do
        for key,prior in pairs(entries) do pcall(function() tbl[key]=prior end) end
        savedTables[tbl]=nil
    end
end
local function scanLocalConfigModules(tool)
    if not Cfg.ModuleConfigs or not tool then return end
    local modules={}
    for _,d in ipairs(tool:GetDescendants()) do
        if d:IsA('ModuleScript') and containsAny(d.Name,{'config','settings','stats','weapon','gun'}) then
            modules[#modules+1]=d
            if #modules>=10 then break end
        end
    end
    for _,module in ipairs(modules) do
        local cached=loadedModules[module]
        if type(cached)=='table' then
            patchConfigTable(cached,0,{}, {n=0})
        elseif not loadingModules[module] then
            loadingModules[module]=true
            task.spawn(function()
                -- Requiring a module may yield; never block the render loop.
                local ok,result=pcall(require,module)
                loadingModules[module]=nil
                if alive and ok and type(result)=='table' then
                    loadedModules[module]=result
                    patchConfigTable(result,0,{}, {n=0})
                end
            end)
        end
    end
end
local function restoreWeaponStats()
    restoreConfigTables()
    for obj, prior in pairs(savedValues) do
        if obj and obj.Parent then pcall(function() obj.Value = prior end) end
        savedValues[obj]=nil
    end
    for obj, attrs in pairs(savedAttrs) do
        if obj and obj.Parent then
            for key,prior in pairs(attrs) do
                pcall(function() obj:SetAttribute(key, prior) end)
            end
        end
        savedAttrs[obj]=nil
    end
end
local function modifyWeaponStats()
    if not Cfg.ScanWeapons then return end
    local character = ch()
    if not character then return end
    local tool = weaponFromModel(character)
    if not tool then return end
    -- Limit scanning to the actual held item; no global registry scans.
    local candidates = {tool}
    for _,d in ipairs(tool:GetDescendants()) do
        if #candidates >= 180 then break end
        if d:IsA('IntValue') or d:IsA('NumberValue') or d:IsA('Configuration')
            or d:IsA('Folder') then candidates[#candidates+1]=d end
    end
    scanLocalConfigModules(tool)
    for _,obj in ipairs(candidates) do
        if obj:IsA('IntValue') or obj:IsA('NumberValue') then
            local kind=keyType(obj.Name)
            if kind and statEnabled(kind) then
                if savedValues[obj]==nil then savedValues[obj]=obj.Value end
                local v=statNumber(kind,savedValues[obj],obj.Name)
                pcall(function() obj.Value = obj:IsA('IntValue') and math.floor(v) or v end)
            end
        end
        for name,value in pairs(obj:GetAttributes()) do
            local kind=keyType(name)
            if type(value)=='number' and kind and statEnabled(kind) then
                if not savedAttrs[obj] then savedAttrs[obj]={} end
                if savedAttrs[obj][name]==nil then savedAttrs[obj][name]=value end
                pcall(function() obj:SetAttribute(name,statNumber(kind,savedAttrs[obj][name],name)) end)
            end
        end
    end
end

-- ============================================================
-- WEAPON PROFILER / SOURCE DISCOVERY (CLIENT-VISIBLE, READ-ONLY)
-- No blind memory addresses, no getgc sweeps, no global hook scans.
-- Never require unknown modules just to list their existence.
-- ============================================================
local weaponProfile={entries={},modules={},scanned=0,updated=0,weapon=nil,running=false,version=0}
local profileLabels=nil
local function sourcePath(obj)
    local ok,p=pcall(function() return obj:GetFullName() end)
    return ok and p or (obj and obj.Name or '?')
end
local function profileEntry(entries,seen,obj,field,kind,source,value,editable)
    local id=source..':'..field
    seen[obj]=seen[obj] or {}
    if seen[obj][id] or #entries>=100 then return end
    seen[obj][id]=true
    entries[#entries+1]={object=obj,field=field,kind=kind,source=source,
        value=value,editable=editable,path=sourcePath(obj)..'.'..field}
end
local function scanWeaponSources()
    if not alive or not Cfg.ScanWeapons or weaponProfile.running then return end
    weaponProfile.running=true
    weaponProfile.version+=1
    local token=weaponProfile.version
    task.spawn(function()
        local tool=weaponFromModel(ch())
        if tool and Cfg.ModuleConfigs then scanLocalConfigModules(tool) end
        local roots,added={},{ }
        local function add(obj,editable,depth)
            if obj and obj.Parent and not added[obj] then
                added[obj]=true
                roots[#roots+1]={obj=obj,editable=editable,depth=depth or 0}
            end
        end
        add(tool,true,0)
        -- Local equipped weapon and nearby replicated config containers first.
        local character=ch()
        if character then
            for _,child in ipairs(character:GetChildren()) do
                if child~=tool and containsAny(child.Name,{'weapon','gun','equip','item','stats','config'}) then
                    add(child,true,0)
                end
            end
        end
        local c=cam()
        if c then
            for _,child in ipairs(c:GetChildren()) do
                if containsAny(child.Name,{'weapon','gun','viewmodel','arm','fps'}) or containsAny(child.Name,WEAPON_HINTS) then add(child,true,0) end
            end
        end
        local backpack=LocalPlayer:FindFirstChildOfClass('Backpack')
        if backpack then
            for _,child in ipairs(backpack:GetChildren()) do
                if child:IsA('Tool') then add(child,false,0) end
            end
        end
        for _,child in ipairs(ReplicatedStorage:GetChildren()) do
            if containsAny(child.Name,{'weapon','gun','config','equipment','arsenal','firearm','itemdata','shared','modules','combat'}) then
                add(child,false,0)
            end
        end
        local playerScripts=LocalPlayer:FindFirstChild('PlayerScripts')
        if playerScripts then
            for _,child in ipairs(playerScripts:GetChildren()) do
                if containsAny(child.Name,{'weapon','gun','combat','shoot','firearm','config','module','fps'}) then
                    add(child,false,0)
                end
            end
        end
        local queue=roots
        local index,scanned=1,0
        local entries,modules,seen={}, {}, {}
        while alive and token==weaponProfile.version and index<=#queue and scanned<1750 do
            local item=queue[index];index+=1
            local obj=item.obj
            scanned+=1
            if obj and obj.Parent then
                if obj:IsA('IntValue') or obj:IsA('NumberValue') then
                    local kind=keyType(obj.Name)
                    if kind then
                        profileEntry(entries,seen,obj,'Value',kind,'Value',obj.Value,item.editable)
                    end
                end
                local ok,attrs=pcall(function() return obj:GetAttributes() end)
                if ok then
                    for key,value in pairs(attrs) do
                        local kind=keyType(key)
                        if kind and type(value)=='number' then
                            profileEntry(entries,seen,obj,key,kind,'Attribute',value,item.editable)
                        end
                    end
                end
                if obj:IsA('ModuleScript') and containsAny(obj.Name,
                    {'config','setting','stat','weapon','gun','recoil','spread','ballistic','shoot'}) then
                    if #modules<30 then modules[#modules+1]=sourcePath(obj) end
                    -- Only opt-in modules under the equipped item can be required.
                    local cached=loadedModules[obj]
                    if type(cached)=='table' then
                        local function walk(tbl,path,depth,visited)
                            if depth>3 or visited[tbl] then return end
                            visited[tbl]=true
                            for key,value in pairs(tbl) do
                                local kind=keyType(key)
                                if type(value)=='number' and kind then
                                    profileEntry(entries,seen,obj,path..'.'..tostring(key),kind,
                                        'ModuleTable',value,item.editable and Cfg.ModuleConfigs)
                                elseif type(value)=='table' then walk(value,path..'.'..tostring(key),depth+1,visited) end
                            end
                        end
                        walk(cached,'return',0,{})
                    end
                end
                if item.depth<7 then
                    for _,child in ipairs(obj:GetChildren()) do
                        if #queue>=2500 then break end
                        queue[#queue+1]={obj=child,editable=item.editable,depth=item.depth+1}
                    end
                end
            end
            if scanned%60==0 then task.wait() end
        end
        if alive and token==weaponProfile.version then
            weaponProfile.entries=entries
            weaponProfile.modules=modules
            weaponProfile.scanned=scanned
            weaponProfile.weapon=tool
            weaponProfile.updated=clock()
        end
        if token==weaponProfile.version then weaponProfile.running=false end
    end)
end
local function showProfileText()
    if not profileLabels then return end
    local profile=weaponProfile
    local editable,spreads=0,0
    local output={}
    for _,e in ipairs(profile.entries) do
        if e.editable then editable+=1 end
        if e.kind=='spread' then spreads+=1 end
        if #output<6 then
            local prefix=e.editable and '● ' or '○ '
            output[#output+1]=prefix..e.kind:upper()..' '..tostring(e.value)
                ..'  ·  '..e.path:sub(-69)
        end
    end
    local msg=('Erkannt: %d Werte | %d lokal editierbar | %d Spread | %d Module (nur erkannt)')
        :format(#profile.entries,editable,spreads,#profile.modules)
    if #output==0 then
        msg=msg..'\nKeine zugänglichen Werte. Waffe: '..(profile.weapon and profile.weapon.Name or 'kein Waffenmodell repliziert')..' – serverseitige/Script-Konstanten bleiben unbekannt.'
    else
        msg=msg..'\n'..table.concat(output,'\n')
    end
    profileLabels.Text=msg
end

local function applyProfiledLocalStats()
    for _,e in ipairs(weaponProfile.entries) do
        local obj=e.object
        if e.editable and obj and obj.Parent and statEnabled(e.kind) then
            if e.source=='Value' and (obj:IsA('IntValue') or obj:IsA('NumberValue')) then
                if savedValues[obj]==nil then savedValues[obj]=obj.Value end
                local v=statNumber(e.kind,savedValues[obj],obj.Name)
                pcall(function() obj.Value=obj:IsA('IntValue') and math.floor(v) or v end)
            elseif e.source=='Attribute' then
                local current=obj:GetAttribute(e.field)
                if type(current)=='number' then
                    if not savedAttrs[obj] then savedAttrs[obj]={} end
                    if savedAttrs[obj][e.field]==nil then savedAttrs[obj][e.field]=current end
                    pcall(function() obj:SetAttribute(e.field,
                        statNumber(e.kind,savedAttrs[obj][e.field],e.field)) end)
                end
            end
        end
    end
end

-- ============================================================
-- TARGET INDEX / NO PHYSICS CASTS / NO GLOBAL PER-FRAME SCANS
-- ============================================================
local npcSet = setmetatable({}, {__mode='k'})
local targetCache = {}
local focusTarget = nil
local focusPart = nil
local targetStamp = 0
local function partFor(model)
    if not model then return nil end
    return model:FindFirstChild('Head') or model:FindFirstChild('UpperTorso')
        or model:FindFirstChild('Torso') or rootOf(model)
end
local function indexNPC(model)
    if not model or not model:IsA('Model') or model==ch() then return end
    if Players:GetPlayerFromCharacter(model) then return end
    local hum=humanoidOf(model)
    if hum and hum.Health > 0 and rootOf(model) then npcSet[model]=true end
end
local function isFriendly(model, player)
    if not Cfg.TeamCheck then return false end
    if player and LocalPlayer.Team and player.Team == LocalPlayer.Team then return true end
    local localChar=ch()
    if model==localChar then return true end
    local rr=rootOf(model)
    if rr and rr:FindFirstChild('TeammateLabel') then return true end
    local status=model:GetAttribute('Team') or model:GetAttribute('Faction')
    local myTeam=localChar and (localChar:GetAttribute('Team') or localChar:GetAttribute('Faction'))
    if status~=nil and myTeam~=nil and status==myTeam then return true end
    return false
end
local function buildTargetCache()
    local result,seen={},{}
    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LocalPlayer and aliveModel(player.Character) and not isFriendly(player.Character,player) then
            seen[player.Character]=true
            result[#result+1]={model=player.Character,player=player}
        end
    end
    if Cfg.TargetNPCs then
        for model in pairs(npcSet) do
            if aliveModel(model) and not seen[model] and not isFriendly(model,nil) then
                result[#result+1]={model=model,player=nil}
            elseif not model.Parent then npcSet[model]=nil end
        end
    end
    targetCache=result
end
local function targetScreen(model)
    local camera=cam()
    local part=partFor(model)
    if not camera or not part then return nil,nil,false end
    local pt,on=camera:WorldToViewportPoint(part.Position)
    if not on or pt.Z <= 0 then return part,nil,false end
    return part,Vector2.new(pt.X,pt.Y),true
end
local function nearestTarget(fov, fromMouse)
    -- Lobby filtering is for ESP only, not for deliberate combat input. 
    local camera=cam()
    if not camera then return nil,nil end
    local center=fromMouse and UserInputService:GetMouseLocation() or (camera.ViewportSize/2)
    local origin=rootOf(ch())
    local best,bestPart,bestScore=nil,nil,math.huge
    for _,t in ipairs(targetCache) do
        local model=t.model
        if aliveModel(model) then
            local part,point,on=targetScreen(model)
            if part and on then
                local worldDistance=origin and (part.Position-origin.Position).Magnitude or 99999
                local score=(point-center).Magnitude
                if worldDistance<=Cfg.TargetRange and score<=fov and score<bestScore then
                    best,bestPart,bestScore=t,part,score
                end
            end
        end
    end
    return best,bestPart
end
local function refreshFocus()
    buildTargetCache()
    focusTarget,focusPart=nearestTarget(Cfg.SilentFOV,false)
    targetStamp=clock()
end

-- Initial scan yields regularly and has a hard budget. New NPCs are event-indexed.
task.spawn(function()
    local q={Workspace}
    local i=1
    local scanned=0
    while alive and i<=#q and scanned<6500 do
        local node=q[i]; i+=1; scanned+=1
        if node:IsA('Model') then indexNPC(node) end
        if node:IsA('Folder') or node:IsA('Model') or node==Workspace then
            for _,child in ipairs(node:GetChildren()) do
                if child:IsA('Model') or child:IsA('Folder') then q[#q+1]=child end
            end
        end
        if scanned%95==0 then task.wait() end
    end
end)
connect(Workspace.DescendantAdded,function(obj)
    if not alive then return end
    if obj:IsA('Humanoid') then
        task.defer(function() if alive then indexNPC(obj.Parent) end end)
    elseif obj:IsA('Model') and containsAny(obj.Name,{'npc','enemy','dummy','bot','target'}) then
        task.defer(function() if alive then indexNPC(obj) end end)
    end
end)

-- ============================================================
-- NETWORK SILENT: NO MOUSE MOVEMENT, NO CAMERA CFrame CHANGES
-- ============================================================
local silentCounts={seen=0,patched=0}
local function muzzlePosition()
    local character=ch()
    local tool=character and weaponFromModel(character)
    if tool then
        local candidate=tool:FindFirstChild('Muzzle',true) or tool:FindFirstChild('Barrel',true)
        if candidate then
            if candidate:IsA('Attachment') then return candidate.WorldPosition end
            if candidate:IsA('BasePart') then return candidate.Position end
        end
        local handle=tool:FindFirstChild('Handle',true)
        if handle and handle:IsA('BasePart') then return handle.Position end
    end
    local head=character and character:FindFirstChild('Head')
    if head then return head.Position end
    local root=rootOf(character)
    return root and root.Position or nil
end
local function editNamedPayload(tbl,targetPos,origin,depth,visited)
    if depth>3 or visited[tbl] then return tbl,false end
    visited[tbl]=true
    local copy,changed={},false
    for key,val in pairs(tbl) do
        local keyText=lower(key):gsub('[^a-z0-9]','')
        if v3(val) and SHOT_KEYS[keyText] then
            if keyText:find('direction',1,true) then
                local diff=targetPos-origin
                if diff.Magnitude>0.01 then
                    copy[key]=diff.Unit*(val.Magnitude>1.1 and val.Magnitude or 1)
                    changed=true
                else copy[key]=val end
            else
                copy[key]=targetPos
                changed=true
            end
        elseif type(val)=='table' then
            local nested,was=editNamedPayload(val,targetPos,origin,depth+1,visited)
            copy[key]=nested
            changed=changed or was
        else copy[key]=val end
    end
    return changed and copy or tbl,changed
end
local function rewriteShotArgs(remote, args)
    local name=lower(remote.Name)
    local likelyShot=containsAny(name,SHOT_REMOTE_WORDS)
    local generic=Cfg.SilentGeneric and containsAny(name,GENERIC_REMOTE_WORDS)
    if not likelyShot and not generic then return nil end
    if not Cfg.Silent or not focusPart or not focusPart.Parent or clock()-targetStamp > 0.5 then return nil end
    if not aliveModel(focusTarget and focusTarget.model) then return nil end
    local origin=muzzlePosition()
    if not origin then return nil end
    local targetPos=focusPart.Position
    local result={n=args.n}
    local changed=false
    for i=1,args.n do
        local v=args[i]
        if type(v)=='table' then
            local newTable,hit=editNamedPayload(v,targetPos,origin,0,{})
            result[i]=newTable
            changed=changed or hit
        else result[i]=v end
    end
    -- A strict known positional pattern: (origin: Vector3, direction: Vector3)
    -- No blind mutation of arbitrary Vector3 remote arguments.
    if not changed and likelyShot and args.n>=2 and v3(args[1]) and v3(args[2]) then
        local dir=targetPos-args[1]
        if dir.Magnitude>0.01 and args[2].Magnitude>0.01 then
            result[2]=dir.Unit*(args[2].Magnitude>1.1 and args[2].Magnitude or 1)
            changed=true
        end
    end
    return changed and result or nil
end
local function installShotBridge()
    local bridge=env.NEXUS_SHOT_BRIDGE
    if bridge then return bridge.active == true end
    if type(hookmetamethod)~='function' or type(getnamecallmethod)~='function' then return false end
    local state={active=true,handler=nil}
    local original
    local fn=function(self,...)
        local method=getnamecallmethod()
        local allow=state.handler~=nil and (method=='FireServer' or method=='InvokeServer')
            and typeof(self)=='Instance'
            and (self:IsA('RemoteEvent') or self:IsA('RemoteFunction'))
        if allow and (type(checkcaller)~='function' or not checkcaller()) then
            local args=table.pack(...)
            local ok,newArgs=pcall(state.handler,self,args)
            if ok and newArgs then
                return original(self,table.unpack(newArgs,1,newArgs.n))
            end
        end
        return original(self,...)
    end
    local wrapped=type(newcclosure)=='function' and newcclosure(fn) or fn
    local ok,prior=pcall(function() return hookmetamethod(game,'__namecall',wrapped) end)
    if not ok or not prior then return false end
    original=prior
    env.NEXUS_SHOT_BRIDGE=state
    return true
end
local function syncShotBridge()
    if not Cfg.Silent then
        if env.NEXUS_SHOT_BRIDGE then env.NEXUS_SHOT_BRIDGE.handler=nil end
        return
    end
    if installShotBridge() and env.NEXUS_SHOT_BRIDGE then
        env.NEXUS_SHOT_BRIDGE.handler=function(remote,args)
            if not alive or not Cfg.Silent then return nil end
            silentCounts.seen+=1
            local patched=rewriteShotArgs(remote,args)
            if patched then
                silentCounts.patched+=1
                log('patched',remote.Name)
            end
            return patched
        end
    end
end

-- ============================================================
-- DROPPED ITEM INDEX / PROMPT + TOUCH PICKUP / NO TELEPORT
-- ============================================================
local LootState={
    entries={}, limit=350,initialLimit=12000,count=0,pausedUntil=0,
    nextAt=0,magnetNextAt=0,running=false,touchAllowed=true,
    pending=setmetatable({}, {__mode='k'}),pendingCount=0,
    pickQueue={}, pickQueueAt=0,
    last=setmetatable({}, {__mode='k'}),
    stats={touch=0,prompt=0,click=0,attempts=0,last='-',paused=0,magnet=0,magnetBlocked=0,
        requested=0,dropRemoved=0,unconfirmed=0,outOfRange=0,unsupported=0,
        ammoIndexed=0,healIndexed=0,healFullSkips=0,diagnosticScans=0},
}
local loot=LootState.entries

-- v0.7: world drop verification. Never index our own gun, its viewmodel,
-- backpack, ammo display, or another player's equipped ammo as a pickup.
function V3.personalOrEquipped(obj)
    if not obj then return true end
    if obj:IsDescendantOf(LocalPlayer) then return true end
    local myChar=ch()
    if myChar and obj:IsDescendantOf(myChar) then return true end
    local a=obj
    local depth=0
    while a and a~=Workspace and depth<18 do
        if a:IsA('Camera') or a:IsA('Backpack') or a:IsA('PlayerGui') or
            a:IsA('ViewportFrame') or (a:IsA('Model') and humanoidOf(a)) then return true end
        if a~=obj and containsAny(a.Name,{'viewmodel','firstperson','equippedweapons','characterweapons','weaponholder','weaponviewmodel'}) then
            return true
        end
        a=a.Parent;depth+=1
    end
    for _,k in ipairs({'OwnerUserId','OwnerId','PlayerUserId','EquippedByUserId'}) do
        local n=obj:GetAttribute(k)
        if (type(n)=='number' and n==LocalPlayer.UserId) or
            (type(n)=='string' and n==tostring(LocalPlayer.UserId)) then return true end
    end
    local owner=obj:GetAttribute('Owner') or obj:GetAttribute('EquippedBy')
    if typeof(owner)=='Instance' and (owner==LocalPlayer or owner==myChar) then return true end
    if type(owner)=='string' and lower(owner)==lower(LocalPlayer.Name) then return true end
    return false
end
-- Pickup models do not have one universal structure.  Some games use a
-- Folder/Model named AmmoBalanced or Health with an otherwise anonymous part;
-- some use a bare Part whose Touched event is attached on the server.  Detect
-- the *world object*, not an arbitrary "ammo" string in somebody's weapon.
function V3.strongPickupName(name)
    local compact=lower(name):gsub('[^%w]','')
    return compact=='ammobalanced' or compact=='health' or compact=='healthpack'
        or compact=='ammodrop' or compact=='ammopickup' or compact=='healthpickup'
end
function V3.lootKindForName(name)
    local n=lower(name)
    if containsAny(n,AMMO_LOOT_KEYS) or n:find('ammobalanced',1,true) then return 'ammo' end
    if containsAny(n,HP_KEYS) then return 'heal' end
    if containsAny(n,WEAPON_HINTS) then return 'weapon' end
    return nil
end
function V3.rootPickupPart(obj)
    if obj:IsA('BasePart') then return obj end
    return obj:FindFirstChild('TouchPart',true)
        or obj:FindFirstChild('PickupPart',true)
        or obj:FindFirstChild('Hitbox',true)
        or obj:FindFirstChild('Handle',true)
        or obj:FindFirstChildWhichIsA('BasePart',true)
end
function V3.isWorldPickup(obj,part)
    if not obj or not obj.Parent or not part or not part.Parent or V3.personalOrEquipped(obj) then return false end
    if not obj:IsDescendantOf(Workspace) then return false end
    local assembly=part.AssemblyRootPart
    if assembly and ch() and assembly:IsDescendantOf(ch()) then return false end
    local a=obj.Parent
    local depth=0
    while a and a~=Workspace and depth<10 do
        if containsAny(a.Name,LOOT_CONTAINER_KEYS) and not
            containsAny(a.Name,{'weaponholder','equipped','playerinventory','inventoryview'}) then return true end
        a=a.Parent;depth+=1
    end
    if obj:IsA('Tool') and obj:IsDescendantOf(Workspace) then return true end
    local evidence=obj:FindFirstChildWhichIsA('ProximityPrompt',true)
        or obj:FindFirstChildWhichIsA('TouchTransmitter',true)
        or obj:FindFirstChildWhichIsA('ClickDetector',true)
    if evidence then return true end
    -- Explicitly named AmmoBalanced / Health touch pickups can be driven by
    -- server Touched connections and have NO visible TouchTransmitter.
    -- Their presence is recognized, not falsely claimed to be collectable.
    if V3.strongPickupName(obj.Name) and part.CanTouch then return true end
    return false
end
local function lootType(obj)
    if not obj or not obj.Parent then return nil end
    if not (obj:IsA('Folder') or obj:IsA('Model') or obj:IsA('Tool') or obj:IsA('BasePart')) then return nil end
    if V3.personalOrEquipped(obj) then return nil end
    -- Prefer the named logical item over its meshes.  But if the parent is a
    -- generic model and *the part itself* says AmmoBalanced, keep the part.
    if obj:IsA('BasePart') and (obj.Parent:IsA('Model') or obj.Parent:IsA('Tool') or obj.Parent:IsA('Folder')) then
        if V3.lootKindForName(obj.Parent.Name) and
            (V3.strongPickupName(obj.Parent.Name) or obj.Parent:IsA('Tool')) then return nil end
        if not V3.lootKindForName(obj.Name) then return nil end
    end
    local kind=V3.lootKindForName(obj.Name)
    for _,key in ipairs({'ItemType','PickupType','LootType','Category','ItemName','Type','ItemClass'}) do
        local value=obj:GetAttribute(key)
        if type(value)=='string' then kind=kind or V3.lootKindForName(value) end
    end
    if not kind and obj:IsA('Tool') then kind='weapon' end
    if not kind then return nil end
    -- Prevent generic 'Drops' folders that match broad weapon names from
    -- stealing the hitbox of one of their many child items.
    if obj:IsA('Folder') and not V3.strongPickupName(obj.Name) and
        not (containsAny(obj.Name,AMMO_LOOT_KEYS) or containsAny(obj.Name,HP_KEYS)) then return nil end
    local part=V3.rootPickupPart(obj)
    if not part or not part:IsA('BasePart') then return nil end
    if not V3.isWorldPickup(obj,part) then return nil end
    return kind,part
end
local function registerLoot(obj)
    if loot[obj] or LootState.count>=LootState.limit then return end
    local kind,part=lootType(obj)
    if kind and part then
        -- A descendant may be added first; don't index both it and a named
        -- ancestor, as that causes duplicate ESP labels + pickup attempts.
        local p=obj.Parent
        while p and p~=Workspace do
            if loot[p] then return end
            p=p.Parent
        end
        loot[obj]={typ=kind,part=part}
        LootState.count+=1
        if kind=='ammo' then LootState.stats.ammoIndexed+=1 end
        if kind=='heal' then LootState.stats.healIndexed+=1 end
    end
end
local function removeLoot(obj)
    local old=loot[obj]
    if old then
        loot[obj]=nil
        LootState.count=math.max(0,LootState.count-1)
        if old.typ=='ammo' then LootState.stats.ammoIndexed=math.max(0,LootState.stats.ammoIndexed-1) end
        if old.typ=='heal' then LootState.stats.healIndexed=math.max(0,LootState.stats.healIndexed-1) end
    end
end
-- Debounced registrations; also accept newly populated AmmoBalanced/Health
-- folders/models whose hitbox appears *after* the container is created.
connect(Workspace.DescendantAdded,function(obj)
    if not alive or LootState.count>=LootState.limit then return end
    local candidate=obj
    if obj:IsA('BasePart') then
        local parent=obj.Parent
        if parent and (parent:IsA('Model') or parent:IsA('Folder') or parent:IsA('Tool'))
            and V3.lootKindForName(parent.Name) then
            candidate=parent
        elseif not V3.lootKindForName(obj.Name) then
            return
        end
    elseif not (obj:IsA('Model') or obj:IsA('Folder') or obj:IsA('Tool')) then return end
    if not V3.lootKindForName(candidate.Name) and not candidate:IsA('Tool') then return end
    if LootState.pending[candidate] or LootState.pendingCount>=45 then return end
    LootState.pending[candidate]=true; LootState.pendingCount+=1
    task.delay(0.15,function()
        LootState.pending[candidate]=nil
        LootState.pendingCount=math.max(0,LootState.pendingCount-1)
        if alive and candidate.Parent then registerLoot(candidate) end
    end)
end)
connect(Workspace.DescendantRemoving,function(obj)
    if loot[obj] then removeLoot(obj) end
end)
-- Initial breadth-first sweep across multiple frames. Old v1.0 capped this
-- at 2,800 objects and silently missed supplies further down in loaded maps.
function V3.scanInitialLoot()
    local queue={Workspace}
    local index,seen=1,0
    while alive and index<=#queue and seen<LootState.initialLimit
        and LootState.count<LootState.limit do
        local node=queue[index];index+=1;seen+=1
        if node:IsA('Model') or node:IsA('Tool') or node:IsA('BasePart') or node:IsA('Folder') then
            if V3.lootKindForName(node.Name) or node:IsA('Tool') then registerLoot(node) end
        end
        if node:IsA('Folder') or node:IsA('Model') or node==Workspace then
            -- Don't recursively scan other players' avatars/equipment.
            if node==Workspace or not V3.personalOrEquipped(node) then
                for _,child in ipairs(node:GetChildren()) do
                    if child:IsA('Folder') or child:IsA('Model') or child:IsA('Tool') or child:IsA('BasePart') then
                        queue[#queue+1]=child
                    end
                end
            end
        end
        if seen%70==0 then task.wait() end
    end
    LootState.stats.last='Loot-Scan: '..tostring(seen)..' Objekte, '..tostring(LootState.count)..' Drops'
end
task.spawn(V3.scanInitialLoot)

-- Actual physics cannot be made invisible to other clients by a LocalScript.
-- We only move genuinely locally-owned, unanchored DROP assemblies. No player TP.
-- Every magnet attempt has a bounded lifespan; a failed pickup is restored.
local function tryMagnetPickup(entry, playerRoot)
    if not Cfg.LootMagnet or not entry or not playerRoot then return false end
    -- A low cooldown must not generate a 10 Hz stream of distant teleports.
    if clock()<LootState.magnetNextAt then return false end
    local part=entry.part
    if not part or not part.Parent or not part:IsA('BasePart') or part.Anchored then return false end
    if not entry.object or not entry.object:IsDescendantOf(Workspace) then return false end
    -- Never assume that a remote/server-owned item may be moved.
    local ownershipQuery=type(isnetworkowner)=='function' and isnetworkowner
        or (type(env.isnetworkowner)=='function' and env.isnetworkowner or nil)
    if not ownershipQuery then
        LootState.stats.unsupported+=1
        LootState.stats.last='Fern-Magnet nicht verfügbar: Netzwerkbesitz nicht prüfbar'
        return false
    end
    local okOwner,ownedLocally=pcall(ownershipQuery,part)
    if not okOwner or not ownedLocally then
        LootState.stats.magnetBlocked+=1
        LootState.stats.last='Fern-Magnet blockiert: Drop ist serverseitig/fremd kontrolliert'
        return false
    end
    local oldCF=part.CFrame
    local oldLocal=part.LocalTransparencyModifier
    local target=playerRoot.Position + playerRoot.CFrame.LookVector*1.5
    local ok=pcall(function()
        part.LocalTransparencyModifier=1 -- Only on THIS client, never globally invisible.
        part.CFrame=CFrame.new(target)*oldCF.Rotation
        part.AssemblyLinearVelocity=Vector3.zero
    end)
    if not ok then
        pcall(function() part.LocalTransparencyModifier=oldLocal end)
        return false
    end
    LootState.stats.magnet+=1
    LootState.magnetNextAt=clock()+0.8
    -- A pickup cannot be forced if the game checks collisions/range server-side.
    task.delay(0.18,function()
        if part and part.Parent then
            pcall(function()
                part.LocalTransparencyModifier=oldLocal
                if entry.object and entry.object:IsDescendantOf(Workspace)
                    and (part.Position-target).Magnitude<8 then
                    part.CFrame=oldCF
                end
            end)
        end
    end)
    return true
end

local function tryTouchPickup(root, part)
    if not LootState.touchAllowed then return false end
    local fn=type(firetouchinterest)=='function' and firetouchinterest
        or (type(env.firetouchinterest)=='function' and env.firetouchinterest or nil)
    if not fn then
        LootState.stats.unsupported+=1
        LootState.stats.last='Keine Touch-Pickup-API in dieser Umgebung'
        return false
    end
    if not root.Parent or not part.Parent then return false end
    local ok=pcall(function()
        fn(root,part,0)
        fn(root,part,1)
    end)
    if ok then LootState.stats.touch+=1 end
    return ok
end
local function tryPickup(entry,root)
    if not alive or not entry.part or not entry.part.Parent
        or not entry.object or not entry.object.Parent then return false end
    LootState.stats.attempts+=1
    local drop=entry.object
    LootState.stats.last='Versuch '..entry.typ..'/'..drop.Name
    local distance=(entry.part.Position-root.Position).Magnitude
    local used=false
    local method=''
    if distance>12 then
        if not tryMagnetPickup(entry,root) then
            LootState.stats.outOfRange+=1
            -- A distant item may be server-owned or never loaded client-side.
            -- This is not a successful pickup, even if an API call returned OK.
            return false
        end
        -- Movement is local only unless this client owns the physical drop.
        used=tryTouchPickup(root,entry.part)
        method='Magnet+Touch'
    else
        -- Native object interactions first. They are much cheaper than repeated
        -- synthetic touches in some executors and games.
        local prompt=drop:FindFirstChildWhichIsA('ProximityPrompt',true)
        local promptFn=type(fireproximityprompt)=='function' and fireproximityprompt
            or (type(env.fireproximityprompt)=='function' and env.fireproximityprompt or nil)
        if prompt and prompt.Enabled and distance<=prompt.MaxActivationDistance and promptFn then
            used=pcall(promptFn,prompt)
            if used then LootState.stats.prompt+=1;method='Prompt' end
        end
        if not used then
            local click=drop:FindFirstChildWhichIsA('ClickDetector',true)
            local clickFn=type(fireclickdetector)=='function' and fireclickdetector
                or (type(env.fireclickdetector)=='function' and env.fireclickdetector or nil)
            if click and distance<=click.MaxActivationDistance and clickFn then
                used=pcall(clickFn,click)
                if used then LootState.stats.click+=1;method='Click' end
            end
        end
        if not used and entry.part.CanTouch then
            used=tryTouchPickup(root,entry.part)
            if used then method='Touch' end
        end
    end
    if used then
        LootState.stats.requested+=1
        LootState.stats.last=method..' gesendet ('..drop.Name..'), Bestätigung ausstehend'
        -- A successful pcall only confirms the *local function invocation*.
        -- Server-side pickup is not demonstrated until the item disappears.
        task.delay(0.55,function()
            if not alive then return end
            if not drop.Parent or not drop:IsDescendantOf(Workspace) then
                LootState.stats.dropRemoved+=1
                LootState.stats.last='Drop entfernt: '..drop.Name
            else
                LootState.stats.unconfirmed+=1
                LootState.stats.last=method..' ohne bestätigten Pickup: '..drop.Name
            end
        end)
    elseif distance<=12 then
        LootState.stats.unsupported+=1
        LootState.stats.last='Kein nutzbarer Pickup-Trigger an '..drop.Name
    end
    return used
end
-- Only ONE global pickup attempt each cooldown (or entire loaded map).
-- Separate short-lived nearest-item cache makes 0.1s selectable without scanning
-- hundreds of drops 10x/sec. Server can reject long-distance fake touches.
local function pickNearbyLoot()
    if not alive or not (Cfg.AutoAmmo or Cfg.AutoHeal) or LootState.running then return end
    local now=clock()
    if now<LootState.pausedUntil or now<LootState.nextAt then return end
    -- The spawn restriction applies to ESP, not picking up ordinary supplies.
    local myRoot=rootOf(ch())
    if not myRoot or not myRoot.Parent then return end
    local radius=Cfg.PickupAnywhere and math.huge
        or math.clamp(tonumber(Cfg.PickupRange) or 500,3,500)
    -- Sorted candidates refreshed only twice per second; do not rescan the
    -- entire loot registry every 0.1 second when the minimum cooldown is set.
    if now>=LootState.pickQueueAt then
        local queue={}
        local position=myRoot.Position
        local health=humanoidOf(ch())
        local needsHeal=health and health.Health>0 and health.Health<health.MaxHealth-0.5
        if Cfg.AutoHeal and not needsHeal and LootState.stats.healIndexed>0 then
            LootState.stats.healFullSkips+=1
        end
        for obj,info in pairs(loot) do
            if not obj.Parent or not info.part.Parent then
                removeLoot(obj)
            elseif ((info.typ=='ammo' and Cfg.AutoAmmo) or
                (info.typ=='heal' and Cfg.AutoHeal and needsHeal))
                and now-(LootState.last[obj] or -100)>=12 then
                local distance=(info.part.Position-position).Magnitude
                if distance<=radius then
                    queue[#queue+1]={object=obj,typ=info.typ,part=info.part,distance=distance}
                end
            end
        end
        table.sort(queue,function(a,b) return a.distance<b.distance end)
        LootState.pickQueue=queue
        LootState.pickQueueAt=now+0.75
    end
    local candidate
    while #LootState.pickQueue>0 do
        local nextItem=table.remove(LootState.pickQueue,1)
        if nextItem.object.Parent and nextItem.part.Parent
            and now-(LootState.last[nextItem.object] or -100)>=12
            and (nextItem.part.Position-myRoot.Position).Magnitude<=radius
            and (((nextItem.part.Position-myRoot.Position).Magnitude<=12)
                or (Cfg.LootMagnet and not nextItem.part.Anchored
                    and (type(isnetworkowner)=='function' or type(env.isnetworkowner)=='function'))) then
            candidate=nextItem
            break
        end
    end
    if not candidate then
        if #LootState.pickQueue==0 and LootState.count>0 then
            local full=humanoidOf(ch())
            if Cfg.AutoHeal and full and full.Health>=full.MaxHealth-0.5 then
                LootState.stats.last='Health nur bei fehlenden HP | Fern-Pickup serverseitig begrenzt'
            else
                LootState.stats.last='Keine erreichbaren Pickup-Interaktionen; entfernte Drops evtl. serverseitig'
            end
        elseif LootState.count==0 then
            LootState.stats.last='Keine Ammo-/Health-Drops indexiert: Loot-Diagnose verwenden'
        end
        return
    end
    LootState.nextAt=now+math.clamp(tonumber(Cfg.PickupCooldown) or 3,0.1,10)
    LootState.last[candidate.object]=now
    LootState.running=true
    task.spawn(function()
        local started=clock()
        local ok,err=pcall(tryPickup,candidate,myRoot)
        LootState.running=false
        if clock()-started>0.15 then
            LootState.pausedUntil=clock()+20
            LootState.touchAllowed=false
            LootState.stats.last='Touch wegen Lag automatisch deaktiviert'
            LootState.stats.paused+=1
        end
        if not ok and Cfg.Debug then warn('[NEXUS/PICKUP]',err) end
    end)
end

-- ============================================================
-- CUSTOM NEXUS OVERLAY: UI-DRAWN CORNERS, ACTUAL LOCAL LIGHTS
-- ============================================================
local guiParent=CoreGui
local guiProps={Name='NEXUS_Client_v1_1',ResetOnSpawn=false,
    IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=1500}
local okParent,sg=pcall(function() return element('ScreenGui',CoreGui,guiProps) end)
if not okParent then
    guiParent=LocalPlayer:WaitForChild('PlayerGui')
    sg=element('ScreenGui',guiParent,guiProps)
end
own(sg)
local overlay=element('Frame',sg,{
    Name='NEXUS_ESP_CANVAS',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    BorderSizePixel=0,Active=false,ClipsDescendants=false,
})
local espRecords={}
local function addCorner(frame,x,y,w,h,col)
    return element('Frame',frame,{
        BackgroundColor3=col,BorderSizePixel=0,
        Position=UDim2.new(x==1 and 1 or 0,x==1 and -w or 0,y==1 and 1 or 0,y==1 and -h or 0),
        Size=UDim2.new(0,w,0,h),
    })
end
local function makeHudFor(model)
    if espRecords[model] then return espRecords[model] end
    local box=element('Frame',overlay,{
        Name='NEXUS_TARGET',BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.fromOffset(60,120),Visible=false,
    })
    local corners={}
    for _,x in ipairs({0,1}) do
        for _,y in ipairs({0,1}) do
            corners[#corners+1]=addCorner(box,x,y,17,2,Palette.cyan)
            corners[#corners+1]=addCorner(box,x,y,2,19,Palette.cyan)
        end
    end
    local name=label(box,'',12,Palette.white,true)
    name.Size=UDim2.new(0,205,0,17)
    name.Position=UDim2.new(0.5,-95,0,-21)
    name.TextXAlignment=Enum.TextXAlignment.Center
    local weapon=label(box,'',10,Palette.tint,true)
    weapon.Size=UDim2.new(0,205,0,17)
    weapon.Position=UDim2.new(0.5,-95,1,4)
    weapon.TextXAlignment=Enum.TextXAlignment.Center
    local inventory=label(box,'',9,Palette.muted,false)
    inventory.Size=UDim2.new(0,230,0,17)
    inventory.Position=UDim2.new(0.5,-110,1,19)
    inventory.TextXAlignment=Enum.TextXAlignment.Center
    local healthBack=element('Frame',box,{
        BackgroundColor3=Palette.bg,BorderSizePixel=0,
        Position=UDim2.fromOffset(-9,0),Size=UDim2.new(0,4,1,0),
    })
    round(healthBack,4)
    local health=element('Frame',healthBack,{
        BackgroundColor3=Palette.green,BorderSizePixel=0,
        AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),
        Size=UDim2.fromScale(1,1),
    })
    round(health,4)
    local hl=element('Highlight',guiParent,{
        Name='NEXUS_VISIBLE_MODEL',Adornee=model,
        DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
        FillTransparency=0.85,OutlineTransparency=0.08,Enabled=false,
        FillColor=Palette.blue,OutlineColor=Palette.cyan,
    })
    local record={box=box,corners=corners,name=name,weapon=weapon,inventory=inventory,
        healthBack=healthBack,health=health,highlight=hl,light=nil,lastInfo=clock()-math.random()*2.0}
    espRecords[model]=record
    return record
end
local function removeHud(model)
    local record=espRecords[model]
    if not record then return end
    safeDestroy(record.box)
    safeDestroy(record.highlight)
    safeDestroy(record.light)
    activeLights[model]=nil
    espRecords[model]=nil
end
local function noHud(rec)
    rec.box.Visible=false
    if rec.highlight then rec.highlight.Enabled=false end
    if rec.light then rec.light.Enabled=false end
end
local function teamColor(player)
    return player and player.Team and player.TeamColor.Color or Palette.cyan
end
local function countLights()
    local n=0
    for model,light in pairs(activeLights) do
        if light and light.Parent and light.Enabled then n+=1
        else activeLights[model]=nil end
    end
    return n
end
V3.weaponNextProbeAt=0
local function espUpdate()
    if not Cfg.ESP or V3.inLobby() then
        for _,rec in pairs(espRecords) do noHud(rec) end
        return
    end
    local camera=cam(); if not camera then return end
    local myRoot=rootOf(ch())
    local active={}
    local n=0
    local lightCount=0
    for _,t in ipairs(targetCache) do
        if n>=Cfg.ESPMax then break end
        local model=t.model
        local hrp=rootOf(model)
        local head=partFor(model)
        if aliveModel(model) and hrp and head and not V3.inSpawnArea(hrp.Position) then
            local distance=myRoot and (myRoot.Position-hrp.Position).Magnitude or 99999
            local pTop,onT=camera:WorldToViewportPoint(head.Position+Vector3.new(0,1.3,0))
            local pBase,onB=camera:WorldToViewportPoint(hrp.Position-Vector3.new(0,3.1,0))
            if (onT or onB) and pTop.Z>0 and pBase.Z>0 and distance<=Cfg.ESPRange then
                local rec=makeHudFor(model)
                active[model]=true; n+=1
                local h=clamp(math.abs(pBase.Y-pTop.Y),25,750)
                local w=clamp(h*0.47,14,300)
                rec.box.Position=UDim2.fromOffset(math.floor(pTop.X-w/2),math.floor(pTop.Y))
                rec.box.Size=UDim2.fromOffset(math.floor(w),math.floor(h))
                rec.box.Visible=Cfg.ESPBox or Cfg.ESPName or Cfg.ESPHealth or Cfg.ESPWeapon
                for _,seg in ipairs(rec.corners) do seg.Visible=Cfg.ESPBox end
                rec.name.Visible=Cfg.ESPName
                local personName=t.player and t.player.DisplayName or model.Name
                rec.name.Text=personName..'  •  '..tostring(math.floor(distance))..'m'
                -- IMPORTANT: never inspect weapon trees inside RenderStepped.
                -- The heartbeat scanner below updates these labels out of band.
                rec.weapon.Visible=Cfg.ESPWeapon or Cfg.ESPAmmo
                rec.inventory.Visible=Cfg.ESPInventory
                local hum=humanoidOf(model)
                local hp=hum and clamp(hum.Health/math.max(1,hum.MaxHealth),0,1) or 1
                rec.healthBack.Visible=Cfg.ESPHealth
                rec.health.Size=UDim2.fromScale(1,hp)
                rec.health.BackgroundColor3=Color3.fromRGB(math.floor(250*(1-hp)),math.floor(230*hp),105)
                rec.highlight.Enabled=Cfg.ESPHighlight
                rec.highlight.FillColor=t.player and teamColor(t.player) or Palette.blue
                rec.highlight.OutlineColor=Palette.cyan
                -- PointLight is an actual locally-rendered 3D light. Cap at six to
                -- avoid severe performance spikes; off by default.
                if Cfg.ESPRealLight and lightCount<Cfg.ESPMaxLight and hrp then
                    if not rec.light or not rec.light.Parent then
                        rec.light=element('PointLight',hrp,{
                            Name='NEXUS_LOCAL_GLOW',Range=11,Brightness=0.55,
                            Color=Palette.cyan,Shadows=false,Enabled=true,
                        })
                        activeLights[model]=rec.light
                    end
                    rec.light.Enabled=true
                    rec.light.Color=Palette.blue:Lerp(Palette.cyan,0.5+math.sin(clock()*2)*0.25)
                    lightCount+=1
                elseif rec.light then rec.light.Enabled=false end
            end
        end
    end
    for model,rec in pairs(espRecords) do
        if not model.Parent then removeHud(model)
        elseif not active[model] then noHud(rec) end
    end
end

-- Scan at most ONE visible character per pass. Weapon lookups are costly
-- in this game; they must never block a RenderStepped update.
V3.weaponRefreshBusy=false
V3.weaponRefreshNext=0
function V3.refreshOneWeaponLabel()
    if V3.weaponRefreshBusy or not Cfg.ESP or V3.inLobby() or
        not (Cfg.ESPWeapon or Cfg.ESPAmmo or Cfg.ESPInventory) then return end
    local now=clock()
    if now<V3.weaponRefreshNext then return end
    local selectedModel,selectedRec=nil,nil
    for model,rec in pairs(espRecords) do
        if rec.box.Visible and model.Parent and now-rec.lastInfo>3.3 then
            selectedModel,selectedRec=model,rec
            break
        end
    end
    if not selectedModel then return end
    V3.weaponRefreshNext=now+0.7
    V3.weaponRefreshBusy=true
    task.spawn(function()
        if alive and selectedModel.Parent then
            local ok,err=pcall(function()
                local _,wn,ammo,reserve=getWeaponInfo(selectedModel)
                if selectedRec and selectedRec.box and selectedRec.box.Parent then
                    selectedRec.weapon.Text=(Cfg.ESPWeapon and wn or 'Munition')
                        ..((Cfg.ESPAmmo and ammo~=nil) and ('  ['..tostring(ammo)
                        ..(reserve and ('/'..tostring(reserve)) or '')..']') or '')
                    selectedRec.inventory.Text=Cfg.ESPInventory
                        and getVisibleInventory(selectedModel) or ''
                    selectedRec.lastInfo=clock()
                end
            end)
            if not ok then log('weapons',err) end
        end
        V3.weaponRefreshBusy=false
    end)
end

-- v0.8 WORLD DROPS. Important separation:
--  (A) build/drop validity + distances at 2.5 Hz, OUTSIDE render frame,
--  (B) only WorldToViewportPoint + UI position in RenderStepped at up to 240 Hz.
--  120 Hz is the default target; actual Hz cannot exceed Roblox render FPS.
local lootOverlay={}
V3.lootVisualCandidates={}
V3.lootVisualCount=0
V3.lootVisualStamp=0

function V3.hideLootOverlay()
    for _,row in ipairs(lootOverlay) do row.Visible=false end
end
function V3.createLootLabel(index)
    local row=label(overlay,'',11,Palette.white,true)
    row.Name='NEXUS_DROP_'..tostring(index)
    row.Size=UDim2.fromOffset(220,26)
    row.TextXAlignment=Enum.TextXAlignment.Center
    row.TextStrokeTransparency=0.48
    return row
end
-- Snapshot only once every ~0.4 seconds. No GetDescendants/Touch testing.
function V3.refreshLootVisualCandidates()
    if not Cfg.ESPDrops or V3.inLobby() then
        V3.lootVisualCount=0
        V3.hideLootOverlay()
        return
    end
    local myRoot=rootOf(ch())
    if not myRoot then V3.lootVisualCount=0;V3.hideLootOverlay();return end
    local origin=myRoot.Position
    local range=math.min(500,Cfg.ESPRange)
    local closest={}
    -- Keep only the displayed 12 candidates; don't sort 32 or change UI every frame.
    local cap=12
    -- Small fixed capped set: no unbounded sort/allocation each render frame.
    for obj,info in pairs(loot) do
        if not obj.Parent or not info.part or not info.part.Parent then
            removeLoot(obj)
        else
            local part=info.part
            local distance=(part.Position-origin).Magnitude
            if distance<=range and not V3.inSpawnArea(part.Position) then
                local item={obj=obj,part=part,kind=info.typ,dist=distance}
                local n=#closest
                local inserted=false
                for j=1,n do
                    if distance<closest[j].dist then
                        table.insert(closest,j,item)
                        inserted=true
                        break
                    end
                end
                if not inserted and n<cap then closest[n+1]=item end
                if #closest>cap then table.remove(closest) end
            end
        end
    end
    V3.lootVisualCandidates=closest
    V3.lootVisualCount=#closest
    V3.lootVisualStamp=clock()
end
function V3.renderLootESP()
    if not Cfg.ESPDrops or V3.inLobby() then V3.hideLootOverlay();return end
    local camera=cam()
    if not camera then V3.hideLootOverlay();return end
    local visible=0
    for i=1,V3.lootVisualCount do
        local entry=V3.lootVisualCandidates[i]
        if entry and entry.part and entry.part.Parent and entry.obj.Parent then
            local p,on=camera:WorldToViewportPoint(entry.part.Position+Vector3.new(0,1.5,0))
            if on and p.Z>0 then
                visible+=1
                if visible>12 then break end
                local row=lootOverlay[visible]
                if not row then
                    row=V3.createLootLabel(visible)
                    lootOverlay[visible]=row
                end
                local kind=entry.kind
                local icon=kind=='ammo' and '[AMMO]' or kind=='heal' and '[HEAL]' or '[WEAPON]'
                local description=icon..' '..entry.obj.Name:sub(1,25)..'  '..math.floor(entry.dist)..'m'
                if row.Text~=description then row.Text=description end
                row.TextColor3=kind=='ammo' and Palette.amber or kind=='heal' and Palette.green or Palette.cyan
                local px,py=math.floor(p.X)-110,math.floor(p.Y)-13
                row.Position=UDim2.fromOffset(px,py)
                row.Visible=true
            end
        end
    end
    for i=visible+1,#lootOverlay do lootOverlay[i].Visible=false end
end

-- Live ViewportFrame. The avatar and weapons are REAL client-replicated meshes,
-- skins, clothing and accessories. The old block-avatar stand-in was removed.
local P={previewPairs={},previewConnections={},previewAngle=0,previewDirty=false}
local function clearWeaponPreview()
    P.weaponPreviewTarget=nil
    P.weaponPreviewModel=nil
    safeDestroy(P.weaponPreviewScene)
    safeDestroy(P.weaponPreviewCamera)
    P.weaponPreviewCamera=nil
    P.weaponPreviewScene=nil
    if P.weaponPreviewViewport then P.weaponPreviewViewport.CurrentCamera=nil end
end
local function clearPreview()
    clearWeaponPreview()
    for _,con in ipairs(P.previewConnections) do pcall(function() con:Disconnect() end) end
    table.clear(P.previewConnections)
    P.previewTarget=nil
    P.previewModel=nil
    table.clear(P.previewPairs)
    safeDestroy(P.previewScene)
    safeDestroy(P.previewCamera)
    P.previewScene=nil
    P.previewCamera=nil
    P.previewDirty=false
    if P.inspectorViewport then P.inspectorViewport.CurrentCamera=nil end
    if P.inspectorLiveBadge then P.inspectorLiveBadge.Text='LIVE MODEL  •  KEIN ZIEL' end
end
local function stripNonVisual(copy)
    for _,d in ipairs(copy:GetDescendants()) do
        if d:IsA('Script') or d:IsA('LocalScript') or d:IsA('ModuleScript')
            or d:IsA('Sound') or d:IsA('ParticleEmitter') or d:IsA('Trail')
            or d:IsA('Beam') or d:IsA('Light') or d:IsA('Highlight')
            or d:IsA('ProximityPrompt') or d:IsA('ClickDetector') then
            safeDestroy(d)
        elseif d:IsA('BasePart') then
            d.Anchored=true; d.CanCollide=false; d.CanTouch=false; d.CanQuery=false
        end
    end
end
local function pairVisibleParts(src,dst,out,maxCount)
    if src:IsA('BasePart') and dst:IsA('BasePart') and #out<maxCount then
        out[#out+1]={source=src,clone=dst}
    end
    local a,b=src:GetChildren(),dst:GetChildren()
    local taken={}
    for _,child in ipairs(a) do
        if #out>=maxCount then break end
        for i,other in ipairs(b) do
            if not taken[i] and child.Name==other.Name and child.ClassName==other.ClassName then
                taken[i]=true
                pairVisibleParts(child,other,out,maxCount)
                break
            end
        end
    end
end
local function exactVisualClone(model,maxParts)
    if not model then return nil,{} end
    maxParts=maxParts or 240
    local originals=model:GetDescendants()
    local oversized=#originals>1500
    local restore={}
    -- Player.Character.Archivable is commonly false. Temporarily enable it,
    -- clone synchronously, then restore every changed flag immediately.
    local function makeArchivable(obj)
        local ok,original=pcall(function() return obj.Archivable end)
        if ok and not original then
            restore[#restore+1]=obj
            pcall(function() obj.Archivable=true end)
        end
    end
    makeArchivable(model)
    for _,obj in ipairs(originals) do makeArchivable(obj) end
    local ok,copy=false,nil
    if not oversized then ok,copy=pcall(function() return model:Clone() end) end
    for i=#restore,1,-1 do pcall(function() restore[i].Archivable=false end) end
    local pairsOut={}
    if ok and copy then
        pairVisibleParts(model,copy,pairsOut,maxParts)
        stripNonVisual(copy)
    end
    if not copy or #pairsOut==0 then
        safeDestroy(copy)
        -- Exact part fallback: clone only actually visible source BaseParts,
        -- including MeshPart textures and part-attached decals. NO proxy avatar.
        copy=Instance.new('Model')
        copy.Name='NEXUS_EXACT_PARTS'
        for _,obj in ipairs(originals) do
            if #pairsOut>=maxParts then break end
            if obj:IsA('BasePart') then
                local old=obj.Archivable
                obj.Archivable=true
                local partOk,partCopy=pcall(function() return obj:Clone() end)
                obj.Archivable=old
                if partOk and partCopy then
                    stripNonVisual(partCopy)
                    partCopy.Anchored=true
                    partCopy.CanCollide=false;partCopy.CanQuery=false;partCopy.CanTouch=false
                    partCopy.Parent=copy
                    pairsOut[#pairsOut+1]={source=obj,clone=partCopy}
                end
            end
        end
    end
    if #pairsOut==0 then safeDestroy(copy);return nil,{} end
    if not copy:IsA('Model') then
        local container=Instance.new('Model')
        container.Name='NEXUS_REAL_'..copy.Name
        copy.Parent=container
        copy=container
    end
    return copy,pairsOut
end
local function showWeaponPreview(tool)
    if P.weaponPreviewTarget==tool then return end
    clearWeaponPreview()
    if not tool or not P.weaponPreviewViewport then return end
    local clone=exactVisualClone(tool,100)
    if not clone then return end
    local scene=element('WorldModel',P.weaponPreviewViewport,{Name='NEXUS_WPN_LIVE_ASSET'})
    local camera=element('Camera',P.weaponPreviewViewport,{FieldOfView=40})
    clone.Parent=scene
    local center,size=clone:GetBoundingBox()
    clone:PivotTo(CFrame.new(0,0,0)*clone:GetPivot():ToObjectSpace(center):Inverse())
    local distance=math.max(2.2,math.max(size.X,size.Y,size.Z)*2.4)
    camera.CFrame=CFrame.lookAt(Vector3.new(distance*0.75,distance*0.3,distance),Vector3.zero)
    P.weaponPreviewViewport.CurrentCamera=camera
    P.weaponPreviewScene=scene
    P.weaponPreviewCamera=camera
    P.weaponPreviewModel=clone
    P.weaponPreviewTarget=tool
end
local function showPreview(model)
    if P.previewTarget==model and not P.previewDirty then return end
    clearPreview()
    if not P.inspectorViewport or not Cfg.ModelPreview or not model then return end
    local clone,pairsOut=exactVisualClone(model,260)
    if not clone then
        P.previewTarget=model
        P.previewDirty=true -- retry if the appearance streams in later
        if P.inspectorLiveBadge then P.inspectorLiveBadge.Text='LIVE MODEL  •  NICHT REPLIZIERT' end
        return
    end
    local scene=element('WorldModel',P.inspectorViewport,{Name='NEXUS_LIVE_AVATAR'})
    local camera=element('Camera',P.inspectorViewport,{FieldOfView=38})
    clone.Parent=scene
    local _,size=clone:GetBoundingBox()
    local distance=math.max(7,size.Y*1.65,size.X*2.3)
    camera.CFrame=CFrame.lookAt(Vector3.new(0,size.Y*0.12,distance),Vector3.new(0,0.45,0))
    P.inspectorViewport.CurrentCamera=camera
    P.previewScene,P.previewCamera,P.previewModel=scene,camera,clone
    P.previewPairs=pairsOut
    P.previewTarget=model
    P.previewAngle=0
    P.previewDirty=false
    if P.inspectorLiveBadge then P.inspectorLiveBadge.Text='● LIVE  •  '..#pairsOut..' ORIGINAL-TEILE' end
    P.previewConnections[#P.previewConnections+1]=model.DescendantAdded:Connect(function(obj)
        if obj:IsA('BasePart') or obj:IsA('Accessory') or obj:IsA('Tool') then P.previewDirty=true end
    end)
    P.previewConnections[#P.previewConnections+1]=model.DescendantRemoving:Connect(function(obj)
        if obj:IsA('BasePart') or obj:IsA('Accessory') or obj:IsA('Tool') then P.previewDirty=true end
    end)
end
local function syncLiveAvatar(dt)
    if not P.previewModel or not P.previewTarget or not P.previewTarget.Parent then return end
    local sourceRoot=rootOf(P.previewTarget)
    if not sourceRoot then return end
    if Cfg.ModelAutoRotate then P.previewAngle=(P.previewAngle+dt*0.47)%(math.pi*2) end
    local yaw=CFrame.Angles(0,P.previewAngle,0)
    local inverse=sourceRoot.CFrame:Inverse()
    for _,pair in ipairs(P.previewPairs) do
        if pair.source.Parent and pair.clone.Parent then
            pair.clone.CFrame=yaw*inverse*pair.source.CFrame
            pair.clone.Transparency=pair.source.Transparency
            pair.clone.Color=pair.source.Color
        end
    end
end
local function updateInspector()
    if not P.inspectorPanel then return end
    if V3.inLobby() then
        P.inspectorName.Text='LOBBY / SPAWN'
        P.inspectorWeapon.Text='ESP deaktiviert'
        P.inspectorAmmo.Text='MUNITION  —'
        P.inspectorInventory.Text='Keine Gegnerdaten im Spawn'
        if P.previewTarget then clearPreview() end
        clearWeaponPreview()
        return
    end
    local t=focusTarget
    -- Inspector remains useful independently of the smaller combat FOV.
    if not t and cam() then t=select(1,nearestTarget(cam().ViewportSize.Magnitude,false)) end
    local model=t and t.model
    if not model or not aliveModel(model) then
        P.inspectorName.Text='KEIN ZIEL'
        P.inspectorWeapon.Text='Waffe  —'
        P.inspectorAmmo.Text='Munition  —'
        P.inspectorInventory.Text='Inventar  nicht verfügbar'
        if P.previewTarget then clearPreview() end
        return
    end
    local enemyTool,wn,ammo,reserve,source=getWeaponInfo(model)
    P.inspectorName.Text=t.player and t.player.DisplayName or model.Name
    P.inspectorWeapon.Text='WAFFE    '..wn
    P.inspectorAmmo.Text='MUNITION    '..(ammo~=nil and tostring(ammo) or '?')
        ..(reserve~=nil and (' / '..reserve) or '')
    P.inspectorInventory.Text='QUELLE   '..source..'\nINVENTAR   '..getVisibleInventory(model)
    if Cfg.ModelPreview then showPreview(model) else clearPreview() end
    showWeaponPreview(enemyTool)
end

-- One-shot diagnosis: helps distinguish "weapon not replicated" from a finder
-- bug. Prints only client-visible nodes and caps the output to avoid lag.
function V3.weaponDiagnosis()
    local selected=focusTarget and focusTarget.model or nil
    if not selected then
        for _,other in ipairs(Players:GetPlayers()) do
            if other~=LocalPlayer and aliveModel(other.Character) then
                selected=other.Character;break
            end
        end
    end
    local targets={ch(),selected}
    for index,model in ipairs(targets) do
        if model then
            local tool,wn,ammo,reserve,src=getWeaponInfo(model)
            print('[NEXUS / WEAPON DIAG]',index==1 and 'LOCAL' or 'TARGET',
                'weapon=',wn,'source=',src,'object=',tool and sourcePath(tool) or '(none)',
                'mag=',ammo or '?','reserve=',reserve or '?')
            local shown,scanned=0,0
            local q={model};local i=1
            while i<=#q and scanned<300 and shown<20 do
                local node=q[i];i+=1;scanned+=1
                if node:IsA('Tool') or containsAny(node.Name,WEAPON_HINTS) or
                    containsAny(node.Name,{'equipment','loadout','muzzle','barrel','viewmodel'}) then
                    print('[NEXUS / WPN NODE]',sourcePath(node),node.ClassName)
                    shown+=1
                end
                if node:IsA('Model') or node:IsA('Folder') or node:IsA('Tool') then
                    for _,child in ipairs(node:GetChildren()) do q[#q+1]=child end
                end
            end
            local rootAttrs=model:GetAttributes()
            for key,value in pairs(rootAttrs) do
                if containsAny(key,{'weapon','gun','equip','loadout','item','active','held'}) then
                    print('[NEXUS / WPN ATTR]',model.Name,key,tostring(value))
                end
            end
            local player=Players:GetPlayerFromCharacter(model)
            local shared,where=V3.readSharedPlayerWeapon(player)
            if shared then print('[NEXUS / WPN PLAYERDATA]',shared,where) end
            local loadout=V3.readEnemyLoadout(model,player,true)
            print('[NEXUS / INVENTORY DIAG]',index==1 and 'LOCAL' or 'TARGET',
                'weapon=',loadout.weapon or '(none)',
                'weaponSource=',loadout.weaponSource or '(none)',
                'inventory=',loadout.inventory,
                'roots=',loadout.roots,'nodes=',loadout.nodes)
            for i,item in ipairs(loadout.items) do
                if i>12 then break end
                print('[NEXUS / INVENTORY ITEM]',i,item,'source=',loadout.sources[i] or '?')
            end
            if shown==0 and not shared then
                print('[NEXUS / WEAPON DIAG] Keine eindeutige replizierte Waffenquelle gefunden; ohne Live-Daten keine verlässliche Identifikation')
            end
        end
    end
end

-- ============================================================
-- NEXUS ORIGINAL GUI | DARK NAVY / NEON BLUE / CUSTOM CONTROLS
-- ============================================================
local main=element('Frame',sg,{
    Name='NEXUS_MAIN',AnchorPoint=Vector2.new(0.5,0.5),
    Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(785,525),
    BackgroundColor3=Palette.bg,BorderSizePixel=0,Visible=Cfg.Menu,
    Active=true,
})
round(main,16);stroke(main,Palette.stroke,1.4)
gradient(main,Palette.pane2,Palette.bg,130)
local sidebar=element('Frame',main,{
    Position=UDim2.fromOffset(0,0),Size=UDim2.new(0,171,1,0),
    BackgroundColor3=Palette.panel,BorderSizePixel=0,
})
round(sidebar,16)
element('Frame',sidebar,{
    Position=UDim2.new(1,-1,0,0),Size=UDim2.new(0,1,1,0),
    BackgroundColor3=Palette.stroke,BorderSizePixel=0,
})
local logo=label(sidebar,'NEXUS',29,Palette.white,true)
logo.Size=UDim2.new(1,-25,0,39);logo.Position=UDim2.fromOffset(18,17)
logo.Font=Enum.Font.GothamBlack
local marker=element('Frame',sidebar,{
    Position=UDim2.fromOffset(18,60),Size=UDim2.fromOffset(34,3),
    BackgroundColor3=Palette.cyan,BorderSizePixel=0,
})
round(marker,3)
local build=label(sidebar,'CLIENT SYSTEM // v0.8',9,Palette.muted,true)
build.Size=UDim2.new(1,-19,0,20);build.Position=UDim2.fromOffset(18,71)
local div=element('Frame',sidebar,{
    Position=UDim2.fromOffset(18,103),Size=UDim2.new(1,-36,0,1),
    BackgroundColor3=Palette.stroke,BorderSizePixel=0,
})
local sidebarList=element('Frame',sidebar,{
    Position=UDim2.fromOffset(9,122),Size=UDim2.new(1,-18,0,338),
    BackgroundTransparency=1,
})
element('UIListLayout',sidebarList,{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
local navButtons={}
local pages={}
local activePage=nil
local title=label(main,'DASHBOARD',22,Palette.white,true)
title.Position=UDim2.fromOffset(196,17)
title.Size=UDim2.new(0,340,0,34)
local subtitle=label(main,'NEXUS ENGINE  •  LIVE CLIENT DATA',10,Palette.muted,true)
subtitle.Position=UDim2.fromOffset(197,50)
subtitle.Size=UDim2.new(0,365,0,17)
local topFlag=label(main,'●  ENGINE ONLINE',10,Palette.green,true)
topFlag.Position=UDim2.new(1,-175,0,24)
topFlag.Size=UDim2.fromOffset(160,24)
topFlag.TextXAlignment=Enum.TextXAlignment.Center
local content=element('Frame',main,{
    Position=UDim2.fromOffset(191,82),Size=UDim2.new(1,-205,1,-125),
    BackgroundTransparency=1,
})
local foot=element('Frame',main,{
    Position=UDim2.new(0,183,1,-34),Size=UDim2.new(1,-195,0,27),
    BackgroundColor3=Palette.panel,BorderSizePixel=0,
})
round(foot,8)
local statusText=label(foot,'ENGINE READY   •   RSHIFT MENU   •   END STOP',10,Palette.muted,true)
statusText.Position=UDim2.fromOffset(12,0);statusText.Size=UDim2.new(1,-24,1,0)

local function makePage(name)
    local scroll=element('ScrollingFrame',content,{
        Name=name,Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,BorderSizePixel=0,Visible=false,
        CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollBarThickness=3,ScrollBarImageColor3=Palette.blue,
    })
    element('UIPadding',scroll,{
        PaddingLeft=UDim.new(0,1),PaddingRight=UDim.new(0,8),
        PaddingBottom=UDim.new(0,14),
    })
    element('UIListLayout',scroll,{
        Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder,
    })
    pages[name]=scroll
    return scroll
end
local function showPage(name)
    activePage=name
    title.Text=name:upper()
    subtitle.Text='NEXUS ENGINE  •  '..name:upper()..' MODULE'
    for key,page in pairs(pages) do page.Visible=key==name end
    for key,row in pairs(navButtons) do
        local selected=key==name
        tween(row,{BackgroundColor3=selected and Palette.tile or Palette.panel},0.16)
        row.TextColor3=selected and Palette.cyan or Palette.muted
    end
end
local function addNav(name,icon,order)
    local row=element('TextButton',sidebarList,{
        LayoutOrder=order,Size=UDim2.new(1,0,0,44),
        BackgroundColor3=Palette.panel,BorderSizePixel=0,
        Text='   '..icon..'   '..name,Font=Enum.Font.GothamBold,
        TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,
        TextColor3=Palette.muted,AutoButtonColor=false,
    })
    round(row,8)
    navButtons[name]=row
    connect(row.MouseButton1Click,function() showPage(name) end)
end
for idx,info in ipairs({
    {'Dashboard','◈'},{'Combat','✦'},{'Visuals','◉'},
    {'Weapons','▰'},{'Loot','⬡'},{'Movement','✧'},{'Settings','⚙'},
}) do
    makePage(info[1]); addNav(info[1],info[2],idx)
end
local below=label(sidebar,'NEXUS // ORIGINAL',10,Palette.cyan,true)
below.Position=UDim2.new(0,17,1,-55)
below.Size=UDim2.new(1,-22,0,19)
local hint=label(sidebar,'RSHIFT  •  MENU',10,Palette.muted)
hint.Position=UDim2.new(0,17,1,-33)
hint.Size=UDim2.new(1,-20,0,18)

local function card(parent,height)
    local row=element('Frame',parent,{
        Size=UDim2.new(1,-5,0,height or 58),BackgroundColor3=Palette.tile,
        BorderSizePixel=0,
    })
    round(row,11);stroke(row,Palette.stroke,0.8,0.35)
    return row
end
local function toggle(parent,text,note,key,callback)
    local box=card(parent,61)
    local l=label(box,text,12,Palette.white,true)
    l.Position=UDim2.fromOffset(15,7);l.Size=UDim2.new(1,-90,0,24)
    local small=label(box,note or '',10,Palette.muted)
    small.Position=UDim2.fromOffset(15,31);small.Size=UDim2.new(1,-88,0,19)
    local track=element('Frame',box,{
        AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-17,0.5,0),
        Size=UDim2.fromOffset(47,25),BorderSizePixel=0,
        BackgroundColor3=Cfg[key] and Palette.blue or Palette.pane2,
    })
    round(track,15)
    local knob=element('Frame',track,{
        Size=UDim2.fromOffset(18,18),BackgroundColor3=Palette.white,
        BorderSizePixel=0,Position=Cfg[key] and UDim2.fromOffset(26,3) or UDim2.fromOffset(3,3),
    })
    round(knob,10)
    local button=element('TextButton',box,{
        BackgroundTransparency=1,Text='',Size=UDim2.fromScale(1,1),AutoButtonColor=false,
    })
    connect(button.MouseButton1Click,function()
        Cfg[key]=not Cfg[key]
        tween(track,{BackgroundColor3=Cfg[key] and Palette.blue or Palette.pane2})
        tween(knob,{Position=Cfg[key] and UDim2.fromOffset(26,3) or UDim2.fromOffset(3,3)})
        if callback then callback(Cfg[key]) end
        Settings.changed()
    end)
    connect(button.MouseEnter,function() tween(box,{BackgroundColor3=Palette.tileHover}) end)
    connect(button.MouseLeave,function() tween(box,{BackgroundColor3=Palette.tile}) end)
    return box
end
local draggingSlider=nil
local sliderSync={}
local function slider(parent,text,key,minimum,maximum,postfix,callback)
    local box=card(parent,73)
    local l=label(box,text,12,Palette.white,true)
    l.Position=UDim2.fromOffset(15,7);l.Size=UDim2.new(1,-100,0,23)
    local value=label(box,tostring(Cfg[key])..(postfix or ''),11,Palette.cyan,true)
    value.Position=UDim2.new(1,-88,0,7);value.Size=UDim2.fromOffset(72,24)
    value.TextXAlignment=Enum.TextXAlignment.Right
    local track=element('Frame',box,{
        Position=UDim2.new(0,16,1,-22),Size=UDim2.new(1,-33,0,7),
        BackgroundColor3=Palette.pane2,BorderSizePixel=0,
    })
    round(track,5)
    local fraction=clamp((Cfg[key]-minimum)/math.max(0.001,maximum-minimum),0,1)
    local fill=element('Frame',track,{
        Size=UDim2.fromScale(fraction,1),BackgroundColor3=Palette.blue,BorderSizePixel=0,
    })
    round(fill,5);gradient(fill,Palette.blue,Palette.cyan,0)
    local knob=element('Frame',track,{
        AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(13,13),
        Position=UDim2.fromScale(fraction,0.5),BackgroundColor3=Palette.white,BorderSizePixel=0,
    })
    round(knob,10);stroke(knob,Palette.cyan,1.2)
    local hit=element('TextButton',box,{
        Text='',BackgroundTransparency=1,Size=UDim2.new(1,-25,0,40),
        Position=UDim2.fromOffset(12,33),AutoButtonColor=false,
    })
    local function setFromMouse()
        local size=math.max(1,track.AbsoluteSize.X)
        local x=clamp((UserInputService:GetMouseLocation().X-track.AbsolutePosition.X)/size,0,1)
        local raw=minimum+(maximum-minimum)*x
        local new=key=='PickupCooldown' and math.floor(raw*10+0.5)/10
            or math.floor(raw+0.5)
        new=clamp(new,minimum,maximum)
        Cfg[key]=new
        for _,sync in ipairs(sliderSync[key] or {}) do sync(new) end
        if callback then callback(new) end
        Settings.changed()
    end
    sliderSync[key]=sliderSync[key] or {}
    sliderSync[key][#sliderSync[key]+1]=function(new)
        local percent=clamp((new-minimum)/math.max(0.001,maximum-minimum),0,1)
        value.Text=tostring(new)..(postfix or '')
        fill.Size=UDim2.fromScale(percent,1)
        knob.Position=UDim2.fromScale(percent,0.5)
    end
    connect(hit.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            draggingSlider=setFromMouse;setFromMouse()
        end
    end)
    return box
end
local function header(parent,text,note)
    local row=element('Frame',parent,{
        Size=UDim2.new(1,-5,0,47),BackgroundTransparency=1,
    })
    local l=label(row,text:upper(),15,Palette.tint,true)
    l.Size=UDim2.new(1,0,0,26)
    local d=label(row,note or '',10,Palette.muted)
    d.Position=UDim2.fromOffset(0,26);d.Size=UDim2.new(1,0,0,18)
end
local function action(parent,name,desc,fn)
    local c=card(parent,62)
    local l=label(c,name,13,Palette.cyan,true)
    l.Position=UDim2.fromOffset(15,8);l.Size=UDim2.new(1,-28,0,24)
    local d=label(c,desc,10,Palette.muted)
    d.Position=UDim2.fromOffset(15,34);d.Size=UDim2.new(1,-28,0,20)
    local b=element('TextButton',c,{
        Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Text='',AutoButtonColor=false,
    })
    connect(b.MouseButton1Click,fn)
    connect(b.MouseEnter,function() tween(c,{BackgroundColor3=Palette.tileHover}) end)
    connect(b.MouseLeave,function() tween(c,{BackgroundColor3=Palette.tile}) end)
end

-- Three live readouts, plus the data-rich enemy 3D inspector.
local dash=pages.Dashboard
header(dash,'System overview','Spielinformation und verfügbare Client-Funktionen')
local overview=card(dash,77)
local ov=label(overview,'NEXUS / ENGINE ONLINE',16,Palette.green,true)
ov.Size=UDim2.new(1,-30,0,29);ov.Position=UDim2.fromOffset(15,10)
local metrics=label(overview,'TARGETS  0   |   DROPS  0   |   SHOTS  0',11,Palette.muted,true)
metrics.Size=UDim2.new(1,-30,0,21);metrics.Position=UDim2.fromOffset(15,42)
local note=card(dash,58)
local nt=label(note,'Alle Anzeigen basieren ausschließlich auf replizierten Daten.',11,Palette.muted)
nt.Position=UDim2.fromOffset(14,10);nt.Size=UDim2.new(1,-28,1,-18)
nt.TextWrapped=true
header(dash,'Gegner Inspektor','Live Modell, sichtbare Waffe, Munition und Inventar')
P.inspectorPanel=card(dash,310)
P.inspectorName=label(P.inspectorPanel,'KEIN ZIEL',15,Palette.white,true)
P.inspectorName.Position=UDim2.fromOffset(14,9)
P.inspectorName.Size=UDim2.new(1,-28,0,24)
P.inspectorViewport=element('ViewportFrame',P.inspectorPanel,{
    Position=UDim2.fromOffset(14,37),Size=UDim2.new(0,205,0,255),
    BackgroundColor3=Palette.panel,BorderSizePixel=0,
    Ambient=Color3.fromRGB(170,195,235),
    LightColor=Palette.cyan,LightDirection=Vector3.new(-1,-0.8,-1),
})
round(P.inspectorViewport,10);stroke(P.inspectorViewport,Palette.stroke)
P.inspectorLiveBadge=label(P.inspectorViewport,'LIVE MODEL  •  KEIN ZIEL',9,Palette.cyan,true)
P.inspectorLiveBadge.Size=UDim2.new(1,-12,0,18)
P.inspectorLiveBadge.Position=UDim2.fromOffset(7,5)
P.inspectorLiveBadge.ZIndex=6
P.inspectorWeapon=label(P.inspectorPanel,'WAFFE  —',12,Palette.tint,true)
P.inspectorWeapon.Position=UDim2.fromOffset(232,49)
P.inspectorWeapon.Size=UDim2.new(1,-244,0,44)
P.inspectorAmmo=label(P.inspectorPanel,'MUNITION  —',12,Palette.amber,true)
P.inspectorAmmo.Position=UDim2.fromOffset(232,101)
P.inspectorAmmo.Size=UDim2.new(1,-244,0,43)
P.inspectorInventory=label(P.inspectorPanel,'INVENTAR  nicht verfügbar',11,Palette.muted)
P.inspectorInventory.Position=UDim2.fromOffset(232,151)
P.inspectorInventory.Size=UDim2.new(1,-245,0,52)
P.inspectorInventory.TextWrapped=true
P.inspectorInventory.TextYAlignment=Enum.TextYAlignment.Top
P.weaponPreviewViewport=element('ViewportFrame',P.inspectorPanel,{
    Position=UDim2.fromOffset(232,209),Size=UDim2.new(1,-248,0,84),
    BackgroundColor3=Palette.panel,BorderSizePixel=0,
    Ambient=Color3.fromRGB(185,210,245),
    LightColor=Palette.cyan,LightDirection=Vector3.new(-1,-1,-1),
})
round(P.weaponPreviewViewport,8);stroke(P.weaponPreviewViewport,Palette.stroke)

local combat=pages.Combat
header(combat,'Combat engine','Schussdaten-Umleitung ohne Kamerasprung oder Mausbewegung')
toggle(combat,'Silent Shot Redirect','Patcht erkennbare Shot-Payloads (spielabhängig)', 'Silent',syncShotBridge)
slider(combat,'Silent Target-FOV','SilentFOV',35,500,' px')
toggle(combat,'Generische Netzwerk-Payloads','Nur bei eindeutig erkannten Ziel-Feldern', 'SilentGeneric')
toggle(combat,'Aim Assist [MB2]','Halte rechte Maustaste; Smoothing 1 = direkter Snap','AimEnabled')
toggle(combat,'Hard Aim über Mausinput','AN: direkter Eingabeschritt; AUS: Kamera-CFrame nach Camera-Update','AimHardInput')
slider(combat,'Aim FOV','AimFOV',40,500,' px')
slider(combat,'Aim Smoothing • 1 = HARD SNAP','AimSmooth',1,20,'')
toggle(combat,'Trigger [MB3]','Zielprüfung via Bildschirmprojektion','Trigger')
slider(combat,'Trigger Radius','TriggerFOV',3,50,' px')
slider(combat,'Trigger CPS','TriggerCPS',1,25,'')
toggle(combat,'NPC Targets','Bots und Trainingsmodelle einbeziehen','TargetNPCs')
toggle(combat,'Teammates ignorieren','Per Players.Team bzw. repliziertem Team-Attribut','TeamCheck')
slider(combat,'Combat Range','TargetRange',100,1500,' studs')

local visuals=pages.Visuals
header(visuals,'Enemy visuals','Eigene Corner-Elemente und Modell-Highlights')
toggle(visuals,'Master ESP','Nur außerhalb von Lobby / Spawn','ESP')
header(visuals,'Lobby-Sperre aktiv','Alle Overlays, Highlights, Lights und Drops im Spawn AUS')
toggle(visuals,'Custom Corner ESP','Eigens erstellte Neon-Corner-Linien','ESPBox')
toggle(visuals,'Name und Distanz','Über der Ziel-Box anzeigen','ESPName')
toggle(visuals,'Health-Anzeige','Dynamischer HP-Balken','ESPHealth')
toggle(visuals,'Equipped Weapon','Nur sichtbare/replizierte Waffen','ESPWeapon')
toggle(visuals,'Gegner-Munition','Nur replizierte Gegner-Werte; niemals eigene Munition','ESPAmmo')
toggle(visuals,'Inventar-Preview','Nur replizierte Informationen','ESPInventory')
toggle(visuals,'Model Highlight','Durch die Szene gerendeter 3D-Outline','ESPHighlight')
toggle(visuals,'Echtes 3D-Licht','Bis zu sechs lokale PointLights, standardmäßig AUS','ESPRealLight')
slider(visuals,'Max aktive Lights','ESPMaxLight',1,6,'')
toggle(visuals,'3D Modell-Viewer','Inspektor im Dashboard','ModelPreview',function(v)
    if not v then clearPreview() end
end)
toggle(visuals,'Modell automatisch rotieren','Viewport-Modell sanft drehen','ModelAutoRotate')
slider(visuals,'ESP Update-Hz','ESPHz',30,240,' Hz')
slider(visuals,'Live Preview-Hz','PreviewHz',10,60,' Hz')
slider(visuals,'Max Targets','ESPMax',5,35,'')
slider(visuals,'ESP Distanz','ESPRange',100,1200,' studs')

local weapons=pages.Weapons
header(weapons,'Weapon lab','v0.9: Gegner-Loadouts, Waffenmodelle, replizierte Inventare & Quellen')
toggle(weapons,'Weapon Scanner','Findet lokale Waffendaten, sofern vorhanden','ScanWeapons')
toggle(weapons,'Module Config Scan','Opt-in: lokale Tool-Config-Module auslesen','ModuleConfigs',function() restoreWeaponStats() end)
toggle(weapons,'No Spread','Lokale Spread/Bloom-Werte = 0, soweit zugänglich','NoSpread',function() restoreWeaponStats() end)
toggle(weapons,'Recoil reduzieren','Ändert lokale Recoil-Werte, falls repliziert','NoRecoil',function() restoreWeaponStats() end)
toggle(weapons,'Fast Fire','RPM/Schussrate erhöhen oder FireInterval reduzieren (lokal)','FastFire',function() restoreWeaponStats() end)
toggle(weapons,'Fast Reload','Lokale Reload-Zeit anpassen','FastReload',function() restoreWeaponStats() end)
toggle(weapons,'Infinite Ammo (lokal)','9999 für verfügbare lokale Ammo-Werte; Server-Werte unverändert','AmmoAssist',function() restoreWeaponStats() end)
local localWeaponInfo=card(weapons,83)
local localWeaponLabel=label(localWeaponInfo,'AKTUELLE WAFFE  —',13,Palette.cyan,true)
localWeaponLabel.Position=UDim2.fromOffset(13,10)
localWeaponLabel.Size=UDim2.new(1,-24,0,25)
local localWeaponData=label(localWeaponInfo,'Lokale Stat-Quelle wird gesucht ...',11,Palette.muted)
localWeaponData.Position=UDim2.fromOffset(13,43)
localWeaponData.Size=UDim2.new(1,-24,0,25)
local weaponProfilerCard=card(weapons,190)
local profileHeader=label(weaponProfilerCard,'WAFFEN-PROFIL  •  QUELLENPRÜFUNG',13,Palette.cyan,true)
profileHeader.Position=UDim2.fromOffset(13,8)
profileHeader.Size=UDim2.new(1,-24,0,24)
profileLabels=label(weaponProfilerCard,'Starte quellengestützte Waffenerkennung ...',10,Palette.muted)
profileLabels.Position=UDim2.fromOffset(13,35)
profileLabels.Size=UDim2.new(1,-24,0,146)
profileLabels.TextWrapped=true
profileLabels.TextYAlignment=Enum.TextYAlignment.Top
action(weapons,'Waffendaten neu analysieren','Tools, ViewModels und replizierte Config-Quellen prüfen',function()
    weaponProfile.version+=1
    weaponProfile.running=false
    scanWeaponSources()
end)
action(weapons,'Waffen + Inventar diagnostizieren','Replizierte Gegner-Quellen und Inventar-Einträge im Output protokollieren',function()
    V3.weaponDiagnosis()
end)
action(weapons,'Waffenwerte wiederherstellen','Stellt alle zuvor geänderten Values/Attribute zurück',function()
    restoreWeaponStats();statusText.Text='NEXUS  •  WAFFENWERTE WIEDERHERGESTELLT'
end)

local lootPage=pages.Loot
header(lootPage,'World drops','Nur echte Welt-Pickups; eigene Munition/Equipment ausgeblendet')
toggle(lootPage,'Dropped-Item ESP','Beschriftung sichtbarer Welt-Items','ESPDrops')
toggle(lootPage,'Auto Ammo Pickup','Max. ein Versuch pro Cooldown; Server kann Distanz prüfen','AutoAmmo')
toggle(lootPage,'Auto Heal Pickup','Bei fehlendem Leben; pro Drop 12 s Pause','AutoHeal')
toggle(lootPage,'Ganze geladene Karte','Nur CLIENT-GELADENE Drops. Kein Streaming-Bypass','PickupAnywhere')
toggle(lootPage,'Drop-Magnet (optional)','Nur lokal kontrollierbare, lose Drops; nicht global unsichtbar','LootMagnet')
slider(lootPage,'Dropped-Item ESP Hz','LootESPHz',30,240,' Hz')
slider(lootPage,'Pickup-Reichweite','PickupRange',3,500,' studs')
slider(lootPage,'Pickup-Cooldown','PickupCooldown',0.1,10,' s')
header(lootPage,'Sicherer Magnet','Charakter bleibt stehen; fremde/serverseitige Drops nicht teleportierbar')
action(lootPage,'Pickup-Diagnose im Output','Zeigt Registrierung, APIs, Blockaden und Bestätigungen',function()
    local s=LootState.stats
    print('[NEXUS/PICKUP DIAG] ammoIndexed='..s.ammoIndexed..' healIndexed='..s.healIndexed
        ..' fullHealthSkips='..s.healFullSkips..' touchAllowed='..tostring(LootState.touchAllowed)
        ..' paused='..tostring(clock()<LootState.pausedUntil))
    print('[NEXUS/PICKUP DIAG] indexed='..LootState.count..' attempts='..s.attempts
        ..' calls='..s.requested..' dropsRemoved='..s.dropRemoved..' unconfirmed='..s.unconfirmed
        ..' magnetBlocked='..s.magnetBlocked..' outOfRange='..s.outOfRange
        ..' unsupported='..s.unsupported..' last='..s.last)
    print('[NEXUS/PICKUP DIAG] firetouchinterest='..tostring(type(firetouchinterest)=='function' or type(env.firetouchinterest)=='function')
        ..' fireproximityprompt='..tostring(type(fireproximityprompt)=='function' or type(env.fireproximityprompt)=='function')
        ..' fireclickdetector='..tostring(type(fireclickdetector)=='function' or type(env.fireclickdetector)=='function')
        ..' isnetworkowner='..tostring(type(isnetworkowner)=='function' or type(env.isnetworkowner)=='function'))
end)
action(lootPage,'AmmoBalanced / Health suchen','Einmalige gefilterte Diagnose; kein Scan im Render-Loop',function()
    task.spawn(function()
        local counts={ammo=0,heal=0,other=0}
        local shown=0
        local nodes={Workspace};local i=1;local inspected=0
        print('[NEXUS/ITEM CHECK] Suche AmmoBalanced / Health in der geladenen Welt ...')
        while alive and i<=#nodes and inspected<18000 do
            local obj=nodes[i];i+=1;inspected+=1
            if obj~=Workspace and (obj:IsA('Model') or obj:IsA('Tool') or obj:IsA('BasePart') or obj:IsA('Folder')) then
                local kind=V3.lootKindForName(obj.Name)
                if kind=='ammo' or kind=='heal' then
                    counts[kind]=counts[kind]+1
                    if shown<18 then
                        shown+=1
                        local part=V3.rootPickupPart(obj)
                        local distance=part and rootOf(ch()) and math.floor((part.Position-rootOf(ch()).Position).Magnitude) or '?'
                        local trigger=part and (obj:FindFirstChildWhichIsA('ProximityPrompt',true)
                            or obj:FindFirstChildWhichIsA('TouchTransmitter',true)
                            or obj:FindFirstChildWhichIsA('ClickDetector',true))
                        print('[NEXUS/ITEM CHECK]',obj:GetFullName(),'type='..kind,
                            'indexed='..tostring(loot[obj]~=nil),'part='..tostring(part and part.Name or '-'),
                            'dist='..tostring(distance),'trigger='..tostring(trigger and trigger.ClassName or 'Touch?'),
                            'anchored='..tostring(part and part.Anchored),'allowed='..tostring(part and V3.isWorldPickup(obj,part)))
                    end
                    if part and not loot[obj] then registerLoot(obj) end
                end
            end
            if obj:IsA('Folder') or obj:IsA('Model') or obj==Workspace then
                if obj==Workspace or not V3.personalOrEquipped(obj) then
                    for _,child in ipairs(obj:GetChildren()) do
                        if child:IsA('Model') or child:IsA('Tool') or child:IsA('BasePart') or child:IsA('Folder') then
                            nodes[#nodes+1]=child
                        end
                    end
                end
            end
            if inspected%80==0 then task.wait() end
        end
        LootState.stats.diagnosticScans+=1
        print('[NEXUS/ITEM CHECK] nodes='..inspected..' ammoMatches='..counts.ammo
            ..' healMatches='..counts.heal..' indexed='..LootState.count
            ..' | Ein gefundener Drop ist keine garantierte Server-Aufnahme.')
    end)
end)
action(lootPage,'Touch-Pickup erneut testen','Nur wenn zuvor automatisch wegen Lag deaktiviert',function()
    LootState.touchAllowed=true
    LootState.pausedUntil=0
    LootState.stats.last='Touch-Test reaktiviert'
end)
action(lootPage,'Loot-Index erneuern','Startet einen begrenzten, frame-schonenden Scan',function()
    task.spawn(function()
        local list=Workspace:GetChildren()
        for i,obj in ipairs(list) do
            if not alive then return end
            registerLoot(obj)
            if obj:IsA('Folder') or obj:IsA('Model') then
                local children=obj:GetChildren()
                for j,child in ipairs(children) do
                    registerLoot(child)
                    if j%60==0 then task.wait() end
                end
            end
            if i%50==0 then task.wait() end
        end
    end)
end)

local move=pages.Movement
header(move,'Movement','Eigene Bewegungssteuerung, nicht server-autoritativ')
toggle(move,'Fly [Z]','Lokale Flugbewegung','Fly')
slider(move,'Fly Speed','FlySpeed',20,200,'')
toggle(move,'Third Person','Kamera-Modus auf Classic / Zoom setzen','ThirdPerson')
toggle(move,'Spin','Lokale Root-Rotation','Spin')
slider(move,'Spin Speed','SpinSpeed',1,8,' turns/s')

local settings=pages.Settings
header(settings,'Performance & safety','Alle Update-Loops werden gedrosselt und bei Stop getrennt')
slider(settings,'Visual Update-FPS','ESPHz',30,240,' Hz')
slider(settings,'Dropped-Item ESP Hz','LootESPHz',30,240,' Hz')
toggle(settings,'Adaptiver Lag-Schutz','Reduziert ESP bei extrem schlechter Frame-Time','AdaptiveVisuals')
slider(settings,'Target Cap','ESPMax',5,35,'')
toggle(settings,'Debug Log','Nur bei aktivem Bedarf','Debug')
header(settings,'Automatische Speicherung','JSON pro Spiel; ohne Datei-API nur Sitzungsspeicher')
action(settings,'Einstellungen jetzt speichern','Schalter + Slider sichern (ohne ständige Dateizugriffe)',function()
    Settings.dirty=true
    local ok=Settings.save(true)
    statusText.Text='NEXUS  •  '..(ok and 'SETTINGS GESPEICHERT' or ('AUTOSAVE: '..Settings.backend))
end)
action(settings,'STOP NEXUS','Alle Verbindungen, Drawings, Lights und Werte aufräumen',function()
    if type(env.NEXUS_STOP)=='function' then env.NEXUS_STOP() end
end)
showPage('Dashboard')

-- Screen-reticle is fully custom Roblox UI, separate from the menu visibility.
local ring=element('Frame',overlay,{
    AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(90,90),
    BackgroundTransparency=1,Visible=false,
})
round(ring,100)
stroke(ring,Palette.cyan,1.4,0.45)
local ringGlow=element('Frame',ring,{
    AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
    Size=UDim2.new(1,10,1,10),BackgroundTransparency=1,
})
round(ringGlow,200)
stroke(ringGlow,Palette.blue,2,0.76)
local ringDot=element('Frame',ring,{
    AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
    Size=UDim2.fromOffset(5,5),BackgroundColor3=Palette.cyan,BorderSizePixel=0,
})
round(ringDot,10)

-- ============================================================
-- INPUT / MOTION / PERFORMANCE SCHEDULER
-- ============================================================
local dragging=false
local dragOrigin=nil
local panelOrigin=nil
connect(main.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        local mouse=UserInputService:GetMouseLocation()
        if mouse.Y < main.AbsolutePosition.Y+75 then
            dragging=true;dragOrigin=input.Position;panelOrigin=main.Position
        end
    end
end)
connect(UserInputService.InputChanged,function(input)
    if input.UserInputType==Enum.UserInputType.MouseMovement then
        if dragging and panelOrigin then
            local delta=input.Position-dragOrigin
            main.Position=UDim2.new(panelOrigin.X.Scale,panelOrigin.X.Offset+delta.X,
                panelOrigin.Y.Scale,panelOrigin.Y.Offset+delta.Y)
        end
        if draggingSlider then draggingSlider() end
    end
end)
connect(UserInputService.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=false;draggingSlider=nil
    end
end)

local F={flyBodyVelocity=nil,flyBodyGyro=nil,flyOldPlatform=nil,wasThirdPerson=false,
    originalCameraMode=LocalPlayer.CameraMode,
    originalMinZoom=LocalPlayer.CameraMinZoomDistance,
    originalMaxZoom=LocalPlayer.CameraMaxZoomDistance}
local function stopFlying()
    safeDestroy(F.flyBodyVelocity);safeDestroy(F.flyBodyGyro)
    F.flyBodyVelocity=nil;F.flyBodyGyro=nil
    local humanoid=humanoidOf(ch())
    if humanoid then humanoid.PlatformStand=F.flyOldPlatform or false end
    F.flyOldPlatform=nil
end
local function runFly()
    if not Cfg.Fly then
        if F.flyBodyVelocity then stopFlying() end
        return
    end
    local character=ch()
    local root=rootOf(character)
    local hum=humanoidOf(character)
    local camera=cam()
    if not root or not hum or not camera then return end
    if not F.flyBodyVelocity or F.flyBodyVelocity.Parent~=root then
        stopFlying()
        F.flyOldPlatform=hum.PlatformStand
        hum.PlatformStand=true
        F.flyBodyVelocity=element('BodyVelocity',root,{
            Name='NEXUS_FLY',MaxForce=Vector3.new(1e8,1e8,1e8),
            Velocity=Vector3.zero,P=12000,
        })
        F.flyBodyGyro=element('BodyGyro',root,{
            Name='NEXUS_FLY_ROT',MaxTorque=Vector3.new(0,1e8,0),
            P=9000,D=320,CFrame=root.CFrame,
        })
    end
    local dir=Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=camera.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir-=camera.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir-=camera.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=camera.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir+=Vector3.yAxis end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir-=Vector3.yAxis end
    F.flyBodyVelocity.Velocity=dir.Magnitude>0 and dir.Unit*Cfg.FlySpeed or Vector3.zero
    local flat=Vector3.new(camera.CFrame.LookVector.X,0,camera.CFrame.LookVector.Z)
    if flat.Magnitude>0.001 then F.flyBodyGyro.CFrame=CFrame.lookAt(root.Position,root.Position+flat) end
end
local function updateThirdPerson()
    if Cfg.ThirdPerson and not F.wasThirdPerson then
        pcall(function()
            LocalPlayer.CameraMode=Enum.CameraMode.Classic
            LocalPlayer.CameraMinZoomDistance=6
            LocalPlayer.CameraMaxZoomDistance=90
        end)
    elseif F.wasThirdPerson and not Cfg.ThirdPerson then
        pcall(function()
            LocalPlayer.CameraMode=F.originalCameraMode
            LocalPlayer.CameraMinZoomDistance=F.originalMinZoom
            LocalPlayer.CameraMaxZoomDistance=F.originalMaxZoom
        end)
    end
    F.wasThirdPerson=Cfg.ThirdPerson
end
local aimHeld=false
local triggerHeld=false
local triggerAt=-1
local aimCachedPart=nil
local aimRescanAt=0
V3.AimRuntime={attempts=0,last='-',applied=0,lastTarget='-'}
local function aimAssist()
    if not alive or not Cfg.AimEnabled or not aimHeld then return end
    local camera=cam()
    if not camera then V3.AimRuntime.last='Kamera nicht verfügbar';return end
    local now=clock()
    if now>=aimRescanAt or not aimCachedPart or not aimCachedPart.Parent then
        local _,part=nearestTarget(Cfg.AimFOV,false)
        aimCachedPart=part
        aimRescanAt=now+0.08
    end
    local part=aimCachedPart
    if not part or not part.Parent then V3.AimRuntime.last='Kein Ziel im FOV / Range';return end
    local p,on=camera:WorldToViewportPoint(part.Position)
    if not on or p.Z<=0 then V3.AimRuntime.last='Ziel außerhalb Bildschirm';return end
    local center=camera.ViewportSize/2
    local dx,dy=p.X-center.X,p.Y-center.Y
    V3.AimRuntime.attempts+=1
    V3.AimRuntime.lastTarget=part.Parent.Name
    if Cfg.AimSmooth<=1 then
        -- Use the game's own mouse look whenever available. In many custom FPS
        -- cameras direct CFrame assignment gets overwritten in the next step.
        local move=type(mousemoverel)=='function' and mousemoverel
            or (type(env.mousemoverel)=='function' and env.mousemoverel or nil)
        if Cfg.AimHardInput and move then
            local ok=pcall(move,dx,dy)
            if ok then V3.AimRuntime.applied+=1;V3.AimRuntime.last='HARD INPUT';return end
        end
        local ok=pcall(function()
            camera.CFrame=CFrame.lookAt(camera.CFrame.Position,part.Position)
        end)
        if ok then V3.AimRuntime.applied+=1;V3.AimRuntime.last='HARD CAMERA'
        else V3.AimRuntime.last='Kamera wird vom Spiel kontrolliert' end
        return
    end
    local move=type(mousemoverel)=='function' and mousemoverel
        or (type(env.mousemoverel)=='function' and env.mousemoverel or nil)
    if not move then V3.AimRuntime.last='Mausinput-API nicht vorhanden';return end
    local ok=pcall(move,dx/Cfg.AimSmooth,dy/Cfg.AimSmooth)
    if ok then V3.AimRuntime.applied+=1;V3.AimRuntime.last='SMOOTH INPUT' end
end
local function fireClick()
    if type(mouse1click)=='function' then
        pcall(mouse1click)
    elseif type(mouse1press)=='function' and type(mouse1release)=='function' then
        pcall(mouse1press)
        task.delay(0.01,function() if alive then pcall(mouse1release) end end)
    end
end
local function triggerStep()
    if not Cfg.Trigger or not triggerHeld then return end
    if clock()-triggerAt < 1/math.max(1,Cfg.TriggerCPS) then return end
    local target,part=nearestTarget(Cfg.TriggerFOV,false)
    if target and part then
        triggerAt=clock()
        fireClick()
    end
end
connect(UserInputService.InputBegan,function(input,handled)
    if not alive then return end
    if input.KeyCode==Enum.KeyCode.End then
        if type(env.NEXUS_STOP)=='function' then env.NEXUS_STOP() end
        return
    end
    if input.KeyCode==Enum.KeyCode.RightShift then
        Cfg.Menu=not Cfg.Menu
        main.Visible=Cfg.Menu
        return
    end
    if handled then return end
    if input.KeyCode==Enum.KeyCode.Z then Cfg.Fly=not Cfg.Fly;Settings.changed() end
    if input.UserInputType==Enum.UserInputType.MouseButton2 then
        aimHeld=true;aimCachedPart=nil;aimRescanAt=0
    end
    if input.UserInputType==Enum.UserInputType.MouseButton3 then triggerHeld=true end
end)
connect(UserInputService.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton2 then
        aimHeld=false;aimCachedPart=nil
    end
    if input.UserInputType==Enum.UserInputType.MouseButton3 then triggerHeld=false end
end)
connect(LocalPlayer.CharacterAdded,function()
    -- Respawning invalidates held tools, targets, local ESP attachments and fly forces.
    stopFlying()
    restoreWeaponStats()
    focusTarget=nil;focusPart=nil
    for model in pairs(espRecords) do removeHud(model) end
    clearPreview()
end)






local R={espMeasured=0,renderedThisSecond=0,renderWindow=0,
    lootMeasured=0,lootRenderedThisSecond=0,lootRenderWindow=0,
    lootAccumulator=0,visualAccumulator=0,modelAccumulator=0,
    lastWeaponProfile=0,lastWeaponObject=nil}
local function boundedTick(current,interval)
    return math.min(current,interval*2)
end
connect(RunService.RenderStepped,function(dt)
    if not alive then return end
    local espInterval=1/math.clamp(Cfg.ESPHz,30,240)
    R.visualAccumulator=boundedTick(R.visualAccumulator+dt,espInterval)
    if R.visualAccumulator>=espInterval then
        R.visualAccumulator=R.visualAccumulator-espInterval
        espUpdate()
        R.renderedThisSecond+=1
    end
    -- Drop HUD position interpolation is independent of the slow loot scanner.
    local visualHz=math.clamp(Cfg.LootESPHz,30,240)
    if Cfg.AdaptiveVisuals and dt>0.055 then visualHz=math.min(visualHz,24) end
    local lootInterval=1/visualHz
    R.lootAccumulator=boundedTick(R.lootAccumulator+dt,lootInterval)
    if R.lootAccumulator>=lootInterval then
        R.lootAccumulator-=lootInterval
        V3.renderLootESP()
        R.lootRenderedThisSecond+=1
    end
    R.lootRenderWindow+=dt
    if R.lootRenderWindow>=1 then
        R.lootMeasured=math.floor(R.lootRenderedThisSecond/R.lootRenderWindow+0.5)
        R.lootRenderedThisSecond=0;R.lootRenderWindow=0
    end
    R.renderWindow+=dt
    if R.renderWindow>=1 then
        R.espMeasured=math.floor(R.renderedThisSecond/R.renderWindow+0.5)
        R.renderedThisSecond=0;R.renderWindow=0
    end
    if Cfg.Menu and Cfg.ModelPreview and P.previewModel then
        local interval=1/math.clamp(Cfg.PreviewHz,10,60)
        R.modelAccumulator=boundedTick(R.modelAccumulator+dt,interval)
        if R.modelAccumulator>=interval then
            R.modelAccumulator-=interval
            local ok,err=pcall(syncLiveAvatar,interval)
            if not ok then log('Live avatar preview error',err) end
        end
    end
end)


local elapsedTargets,elapsedLoot,elapsedInfo,elapsedStats,elapsedWeapon=0,0,0,0,0
local elapsedPickup=0
local elapsedFPS,frames=0,0
local engineConn=connect(RunService.Heartbeat,function(dt)
    if not alive then return end
    -- If Roblox visibly stalls, suspend synthetic pickup activity temporarily.
    if dt>0.17 then LootState.pausedUntil=math.max(LootState.pausedUntil,clock()+8) end
    dt=math.min(dt,0.1)
    elapsedTargets+=dt
    elapsedLoot+=dt
    elapsedPickup+=dt
    elapsedInfo+=dt
    elapsedStats+=dt
    elapsedWeapon+=dt
    elapsedFPS+=dt
    frames+=1
    if elapsedTargets>=(aimHeld and 0.12 or 0.30) then
        elapsedTargets=0
        refreshFocus()
    end
    -- Refresh nearest-drop snapshot every 0.25s; render separately up to 120 Hz.
    if elapsedLoot>=0.25 then
        elapsedLoot=0
        V3.refreshLootVisualCandidates()
    end
    if elapsedPickup>=0.10 then
        elapsedPickup=0
        pickNearbyLoot()
    end
    if elapsedInfo>=1.50 then
        elapsedInfo=0
        if Settings.dirty and clock()-Settings.lastChanged>=1.5 then
            Settings.save(false)
        end
        if Cfg.Menu then updateInspector() end
        local myW,wn,ammo=getWeaponInfo(ch())
        localWeaponLabel.Text='CURRENT  •  '..wn
        localWeaponData.Text=(myW and (sourcePath(myW):sub(-50)) or 'Nicht repliziert')
           ..'  |  MAG  '..(ammo~=nil and tostring(ammo) or '?')
        showProfileText()
        metrics.Text='TARGETS  '..tostring(#targetCache)
            ..'  |  DROPS  '..tostring((function() local n=0 for _ in pairs(loot) do n+=1 end return n end)())
            ..'  |  PICKUP-VERSUCHE  '..tostring(LootState.stats.attempts)
            ..'  |  MAGNET '..tostring(LootState.stats.magnet)
            ..'  |  PICKUPS? '..tostring(LootState.stats.dropRemoved)
            ..'  |  LETZT '..tostring(LootState.stats.last):sub(1,48)
            ..(LootState.touchAllowed and '' or '  |  TOUCH AUS (LAG-SCHUTZ)')
    end
    V3.refreshOneWeaponLabel()
    if elapsedWeapon>=1.50 and Cfg.ScanWeapons and not weaponProfile.running then
        elapsedWeapon=0
        local activeTool=weaponFromModel(ch())
        if activeTool~=R.lastWeaponObject or clock()-R.lastWeaponProfile>7 then
            if activeTool~=R.lastWeaponObject then restoreWeaponStats() end
            R.lastWeaponObject=activeTool
            R.lastWeaponProfile=clock()
            scanWeaponSources()
        end
    end
    if elapsedStats>=1.0 then
        elapsedStats=0
        if Cfg.NoSpread or Cfg.NoRecoil or Cfg.FastFire or Cfg.FastReload or Cfg.AmmoAssist then
            modifyWeaponStats()
            applyProfiledLocalStats()
        end
    end
    if elapsedFPS>=1 then
        local fps=math.floor(frames/math.max(elapsedFPS,0.01))
        frames=0;elapsedFPS=0
        statusText.Text='FPS  '..fps..'  •  ESP '..R.espMeasured..'Hz  •  DROPS '..R.lootMeasured..'/'..Cfg.LootESPHz..'Hz  •  '
            ..(V3.inLobby() and 'LOBBY: ESP GESPERRT' or (Cfg.Silent and 'SILENT ACTIVE' or 'SILENT OFF'))
            ..'  •  SAVE '..Settings.backend..'  •  RSHIFT / END'
    end
    local camera=cam()
    if camera and not V3.inLobby() and (Cfg.Silent or Cfg.AimEnabled) then
        local radius=Cfg.Silent and Cfg.SilentFOV or Cfg.AimFOV
        ring.Visible=true
        ring.Size=UDim2.fromOffset(radius*2,radius*2)
        ring.Position=UDim2.fromOffset(camera.ViewportSize.X/2,camera.ViewportSize.Y/2)
        local part=focusPart
        ringDot.BackgroundColor3=part and Palette.green or Palette.cyan
    else ring.Visible=false end
    if Cfg.Menu and Cfg.ModelAutoRotate and P.weaponPreviewModel then
        pcall(function() P.weaponPreviewModel:PivotTo(CFrame.Angles(0,clock()*0.75,0)) end)
    end
    if Cfg.Fly or F.flyBodyVelocity then runFly() end
    if Cfg.Spin and not Cfg.Fly then
        local myRoot=rootOf(ch())
        if myRoot then
            pcall(function()
                myRoot.CFrame=myRoot.CFrame*CFrame.Angles(0,dt*Cfg.SpinSpeed*2*math.pi,0)
            end)
        end
    end
    if Cfg.ThirdPerson~=F.wasThirdPerson then updateThirdPerson() end
    if triggerHeld then triggerStep() end
end)

-- Camera updates usually happen at priority Camera; run AFTER them.
V3.hardAimRenderName='NEXUS_HARD_AIM_v1_0'
RunService:BindToRenderStep(V3.hardAimRenderName,Enum.RenderPriority.Camera.Value+10,function()
    if alive and aimHeld then aimAssist() end
end)

-- A single idempotent shutdown function; repeated execution does not multiply loops.
local function stopNexus()
    if not alive then return end
    Settings.save(true)
    alive=false
    Cfg.Fly=false;Cfg.Silent=false
    if env.NEXUS_SHOT_BRIDGE then env.NEXUS_SHOT_BRIDGE.handler=nil end
    stopFlying()
    restoreWeaponStats()
    weaponProfile.version+=1
    if F.wasThirdPerson then
        Cfg.ThirdPerson=false
        updateThirdPerson()
    end
    pcall(function() RunService:UnbindFromRenderStep(V3.hardAimRenderName) end)
    for _,con in ipairs(connections) do pcall(function() con:Disconnect() end) end
    for model in pairs(espRecords) do removeHud(model) end
    for obj,u in pairs(lootOverlay) do safeDestroy(u);lootOverlay[obj]=nil end
    clearPreview()
    for _,inst in ipairs(owned) do safeDestroy(inst) end
    if env.NEXUS_STOP==stopNexus then env.NEXUS_STOP=nil end
end
env.NEXUS_STOP=stopNexus
env.NEXUS_STATUS=function()
    return {alive=alive, saveBackend=Settings.backend, saveFile=Settings.path, pickupAttempts=LootState.stats.attempts, pickupLast=LootState.stats.last, ammoIndexed=LootState.stats.ammoIndexed, healIndexed=LootState.stats.healIndexed, fullHealthSkips=LootState.stats.healFullSkips, touchAllowed=LootState.touchAllowed, pickupRequested=LootState.stats.requested, dropRemoved=LootState.stats.dropRemoved, pickupUnconfirmed=LootState.stats.unconfirmed, aimLast=V3.AimRuntime.last, aimAttempts=V3.AimRuntime.attempts, aimApplied=V3.AimRuntime.applied, targets=#targetCache, shotCalls=silentCounts.seen,
        rewrittenShots=silentCounts.patched, lootESPHz=R.lootMeasured, lootESPTargetHz=Cfg.LootESPHz, lootIndexed=LootState.count, magnetMoves=LootState.stats.magnet, magnetBlocked=LootState.stats.magnetBlocked, hudCount=(function() local n=0 for _ in pairs(espRecords) do n+=1 end return n end)(),
        features={Silent=Cfg.Silent,NoSpread=Cfg.NoSpread,ESP=Cfg.ESP}}
end
syncShotBridge()
refreshFocus()
scanWeaponSources()
print('[NEXUS v1.1] loaded | AmmoBalanced/Health discovery | guarded pickup | auto-save: '..Settings.backend..' | RightShift menu | End stop')
