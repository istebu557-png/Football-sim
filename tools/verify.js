#!/usr/bin/env node
/**
 * verify.js — TEK KOMUTLA TAM DOĞRULAMA
 *
 *   npm run verify
 *
 * Roblox entegrasyonunun tamamını baştan sona denetler. Her kapı (gate) kendi
 * alanında "çalışıyor mu?" sorusuna kanıtla cevap verir; biri bile kırmızıysa
 * süreç 1 döner.
 *
 *  1  ortam        Node + Lua VM (fengari) kurulu ve çalışıyor mu
 *  2  sözdizimi     Roblox'a giden her dosya + kurulum dosyası derleniyor mu
 *  3  dil           Roblox Luau'da ÇALIŞMAYACAK sözdizimi/API var mı
 *  4  api           Kullanılan servis/sınıf/Enum/özellik/metot gerçek Roblox
 *                   API'si mi (yazım hatası burada patlar)
 *  5  sınır         Sunucu/istemci/paylaşılan dosyalar doğru tarafta mı
 *  6  kurulum       install/FootballSim_Install.lua kaynaklarla bit-bit senkron mu
 *  7  rojo          default.project.json src/'nin TAMAMINI eşliyor mu
 *  8  remote        İstemci ↔ sunucu remote sözleşmesi (ad, argüman, payload)
 *  9  testler       Motor + kurulum + sunucu + istemci testleri (spec)
 * 10  fizik izi     trace.json üretimi, şeması ve fiziksel sağlamlığı
 * 11  anim izi      anim.json üretimi, şeması ve FK verisi
 * 12  önizleme      preview sunucusu HTTP üzerinden gerçekten servis ediyor mu
 * 13  belge         README'deki sayılar/komutlar gerçekle uyumlu mu
 *
 * Not: Bu araç geliştirme/doğrulama aracıdır; oyuna gitmez (Roblox'a yalnızca
 * src/ ve install/ gider).
 */
"use strict";

const fs = require("fs");
const path = require("path");
const http = require("http");
const net = require("net");
const { spawnSync, spawn } = require("child_process");
const installerLib = require("./installer_lib");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "src");
const BUILD = path.join(ROOT, ".build");
const PREVIEW = path.join(ROOT, "preview");
const FENGARI = path.join(ROOT, "node_modules", ".bin", "fengari");

const MIN_TESTS = 123; // spec.luau'daki en az kontrol sayısı (geriye gitmesin)

/* ------------------------------------------------------------------ yardımcılar */

function walk(dir, filter, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, filter, out);
    else if (filter(full)) out.push(full);
  }
  return out.sort();
}

const rel = (p) => path.relative(ROOT, p).split(path.sep).join("/");

/** tools/runner.js ile aynı normalizasyon: \r\n -> \n, sondaki boşluk atılır. */
function normalizeLineEndings(src) {
  return src.replace(/\r\n/g, "\n").replace(/\s+$/, "");
}

function luaString(s) {
  return (
    '"' +
    s
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\r/g, "")
      .replace(/\n/g, "\\n")
      .replace(/\t/g, "\\t") +
    '"'
  );
}

/** Lua kaynağından yorum ve string gövdelerini çıkarır (satır numaraları korunur).
 *  Böylece statik taramalar "//" içeren bir URL'yi ya da yorumdaki "goto"yu
 *  kod sanmaz. */
/** Yorumları (ve istenirse string gövdelerini) boşluğa çevirir; satır numaraları korunur. */
function stripLua(src, keepStrings) {
  let out = "";
  let i = 0;
  const n = src.length;
  const blank = (s) => s.replace(/[^\n]/g, " ");
  while (i < n) {
    const c = src[i];
    // uzun yorum / uzun string seviyesi
    if (c === "-" && src[i + 1] === "-" && src[i + 2] === "[") {
      let j = i + 3;
      let eq = 0;
      while (src[j] === "=") {
        eq++;
        j++;
      }
      if (src[j] === "[") {
        const close = "]" + "=".repeat(eq) + "]";
        const end = src.indexOf(close, j + 1);
        const stop = end === -1 ? n : end + close.length;
        out += blank(src.slice(i, stop));
        i = stop;
        continue;
      }
    }
    if (c === "-" && src[i + 1] === "-") {
      let j = i;
      while (j < n && src[j] !== "\n") j++;
      out += blank(src.slice(i, j));
      i = j;
      continue;
    }
    if (c === "[") {
      let j = i + 1;
      let eq = 0;
      while (src[j] === "=") {
        eq++;
        j++;
      }
      if (src[j] === "[") {
        const close = "]" + "=".repeat(eq) + "]";
        const end = src.indexOf(close, j + 1);
        const stop = end === -1 ? n : end + close.length;
        out += blank(src.slice(i, stop));
        i = stop;
        continue;
      }
    }
    if (c === '"' || c === "'") {
      const quote = c;
      let j = i + 1;
      while (j < n) {
        if (src[j] === "\\") {
          j += 2;
          continue;
        }
        if (src[j] === quote || src[j] === "\n") {
          j++;
          break;
        }
        j++;
      }
      out += keepStrings ? src.slice(i, j) : blank(src.slice(i, j));
      i = j;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

/** Yorumlar elenir, string gövdeleri KORUNUR (remote adı gibi sabitleri aramak için). */
function maskLua(src) {
  return stripLua(src, true);
}

function lineOf(src, index) {
  return src.slice(0, index).split("\n").length;
}

/** Roblox'a giden dosyalar: src/** + kurulum gövdesi (bootstrap). */
function shippedFiles() {
  const files = walk(SRC, (f) => f.endsWith(".luau"));
  files.push(path.join(ROOT, "tools", "installer", "bootstrap.lua"));
  return files;
}

function runFengari(scriptPath) {
  const r = spawnSync(FENGARI, [scriptPath], { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (r.error) return { ok: false, stdout: "", stderr: "fengari çalıştırılamadı: " + (r.error.code || r.error.message) };
  return { ok: r.status === 0, stdout: r.stdout || "", stderr: r.stderr || "", status: r.status };
}

function runNodeScript(args) {
  const r = spawnSync(process.execPath, args, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (r.error) return { ok: false, stdout: "", stderr: String(r.error.message || r.error) };
  return { ok: r.status === 0, stdout: r.stdout || "", stderr: r.stderr || "", status: r.status };
}

/* ------------------------------------------------------------- Roblox API listeleri */

const ROBLOX_SERVICES = new Set([
  "Workspace", "Players", "Lighting", "ReplicatedStorage", "ReplicatedFirst",
  "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui", "StarterPack",
  "StarterCharacterScripts", "RunService", "UserInputService", "ContextActionService",
  "SoundService", "Debris", "TweenService", "MarketplaceService", "HttpService",
  "CollectionService", "Teams", "PathfindingService", "PhysicsService", "TextChatService",
  "Chat", "TeleportService", "MessagingService", "DataStoreService", "MemoryStoreService",
  "LogService", "ScriptContext", "ScriptService", "GamePassService", "BadgeService",
  "AssetService", "InsertService", "LocalizationService", "PolicyService", "AnalyticsService",
  "AdService", "VRService", "HapticService", "TracerService", "KeyboardService",
  "MouseService", "VirtualInputManager", "TouchInputService", "GuiService", "CoreGui",
  "RobloxReplicatedStorage", "HttpRbxApiService", "NetworkClient", "NetworkSettings",
  "PackageService", "PermissionsService", "PointsService", "ProximityPromptService",
  "PublishService", "RbxAnalyticsService", "RemoteDebuggerService", "RuntimeScriptService",
  "Selection", "ServerScriptServiceInternal", "SessionService", "SocialService",
  "Studio", "StudioData", "StudioDeviceEmulatorService", "StudioService", "TaskScheduler",
  "TestService", "ThirdPartyUserService", "TimerService", "ToastNotificationService",
  "ToolboxService", "TutorialService", "UnvalidatedAssetService", "VersionControlService",
  "VirtualUser", "Visit", "DraggerService", "FacialAnimationRecordingService",
  "FacialAnimationStreamingServiceV1", "FriendService", "Geometry", "GoogleAnalyticsConfiguration",
  "GroupService", "HSService", "InsertService2", "JobId", "LegacyAnalyticsService",
  "LibraryService", "LuauScriptAnalyzer", "MemStorageService", "NotificationService",
]);

const ROBLOX_CLASSES = new Set([
  "Part", "MeshPart", "TrussPart", "WedgePart", "CornerWedgePart", "SpawnLocation",
  "Model", "Folder", "Script", "LocalScript", "ModuleScript", "ScreenGui", "Frame",
  "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "CanvasGroup",
  "ScrollingFrame", "ViewportFrame", "BillboardGui", "SurfaceGui", "UICorner",
  "UIStroke", "UIListLayout", "UIGridLayout", "UIPadding", "UIScale", "UITextSizePresets",
  "UIAspectRatioConstraint", "UISizeConstraint", "Attachment", "Trail", "Beam",
  "ParticleEmitter", "Fire", "Smoke", "Sparkles", "Explosion", "PointLight", "SpotLight",
  "SurfaceLight", "Sound", "SoundGroup", "RemoteEvent", "RemoteFunction", "BindableEvent",
  "BindableFunction", "Atmosphere", "Sky", "BlurEffect", "BloomEffect", "ColorCorrectionEffect",
  "DepthOfFieldEffect", "SunRaysEffect", "Camera", "Humanoid", "HumanoidDescription",
  "Motor6D", "Animation", "AnimationController", "Animator", "Tool", "ClickDetector",
  "ProximityPrompt", "BlockMesh", "CylinderMesh", "FileMesh", "SpecialMesh",
  "CharacterMesh", "BodyColors", "Shirt", "Pants", "ShirtGraphic", "Accessory",
  "Decal", "Texture", "Hole", "Motor", "Rotate", "RotateP", "RotateV", "Glue",
  "Snap", "VelocityMotor", "Weld", "WeldConstraint", "SpringConstraint", "RopeConstraint",
  "RodConstraint", "HingeConstraint", "BallSocketConstraint", "UniversalConstraint",
  "PrismaticConstraint", "CylindricalConstraint", "LineForce", "AngularVelocity",
  "AlignOrientation", "AlignPosition", "VectorForce", "BodyAngularVelocity",
  "BodyColor", "BodyForce", "BodyGyro", "BodyPosition", "BodyThrust", "BodyVelocity",
  "RocketPropulsion", "PointAtConstraint", "NoCollisionConstraint", "Terrain",
  "BasePart", "PVInstance", "Configuration", "BoolValue", "IntValue", "NumberValue",
  "StringValue", "ObjectValue", "Color3Value", "Vector3Value", "CFrameValue",
  "BrickColorValue", "RayValue", "DoubleConstrainedValue", "IntConstrainedValue",
  "TextChannel", "VoiceChannel", "Highlight", "SelectionBox", "SelectionSphere",
  "ArcHandles", "Handles", "SurfaceSelection", "BoxHandleAdornment", "ConeHandleAdornment",
  "CylinderHandleAdornment", "SphereHandleAdornment", "LineHandleAdornment",
  "ImageHandleAdornment", "ForceField", "Player", "Team", "Teams", "Workspace",
]);

const ROBLOX_ENUMS = {
  Material: new Set(["Plastic", "Wood", "Slate", "Concrete", "CorrodedMetal", "DiamondPlate",
    "Foil", "Grass", "Ice", "Marble", "Granite", "Brick", "Pebble", "Sand", "Fabric",
    "SmoothPlastic", "Metal", "WoodPlanks", "Neon", "Glass", "Asphalt", "Basalt",
    "Cobblestone", "Crystal", "Dirt", "Glacier", "Gravel", "Iron", "Lava", "Limestone",
    "Mud", "Pavement", "Rock", "Salt", "Sandstone", "Snow", "Water", "LeafyGrass",
    "Air", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles", "Coal", "ConcreteSlab"]),
  PartType: new Set(["Block", "Ball", "Cylinder", "Wedge", "CornerWedge"]),
  SurfaceType: new Set(["Smooth", "Inlet", "Universal", "Studs", "Weld", "Glue", "Hinge",
    "Motor", "SteppingMotor", "Unjoin"]),
  KeyCode: new Set(["Unknown", "Backspace", "Tab", "Clear", "Return", "Pause", "Escape",
    "Space", "PageUp", "PageDown", "End", "Home", "Left", "Up", "Right", "Down",
    "Insert", "Delete", "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
    "Eight", "Nine", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "NumLock",
    "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt",
    "LeftMeta", "RightMeta", "Semicolon", "Plus", "Comma", "Minus", "Period", "Slash",
    "BackSlash", "Backquote", "LeftBracket", "RightBracket", "Quote", "F1", "F2", "F3",
    "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "KeypadZero",
    "ButtonA", "ButtonB", "ButtonX", "ButtonY", "DPadUp", "DPadDown", "DPadLeft", "DPadRight"]),
  HumanoidStateType: new Set(["FallingDown", "Running", "RunningNoPhysics", "Swimming",
    "Freefall", "GettingUp", "Jumping", "Landed", "Flying", "OnFire", "Dead", "Physics",
    "PlatformStanding", "Ragdoll", "Seated", "Climbing", "None", "StraightFalling"]),
  Font: new Set(["Legacy", "Arial", "ArialBold", "SourceSans", "SourceSansBold",
    "SourceSansSemibold", "SourceSansLight", "SourceSansItalic", "Gotham", "GothamSemibold",
    "GothamBold", "GothamBlack", "GothamLight", "GothamThin", "GothamExtraBold",
    "GothamMedium", "GothamItalic", "GothamMediumItalic", "GothamBoldItalic",
    "GothamBlackItalic", "AmaticSC", "Antique", "Arcade", "Bangers", "BuilderFont",
    "Cartoon", "Code", "Creator", "Denmark", "Fantasy", "FredokaOne", "Garamond",
    "GrenzeGotisch", "Highway", "IndieFlower", "Jura", "Kalam", "LuckiestGuy",
    "Merriweather", "Michroma", "Nunito", "Oswald", "PatrickHand", "PermanentMarker",
    "RobotoCondensed", "RobotoMono", "Sarpanch", "SciFi", "SpecialElite", "TitilliumWeb",
    "Ubuntu", "Fondamento", "JosefinSans", "Inconsolata"]),
  CameraType: new Set(["Fixed", "Watch", "Attach", "Track", "Follow", "Orbital", "Custom",
    "Scriptable"]),
  UserInputType: new Set(["MouseButton1", "MouseButton2", "MouseButton3", "MouseWheel",
    "MouseMovement", "Touch", "Keyboard", "Gamepad1", "Gamepad2", "Accelerometer",
    "Gyro", "None", "TextInput", "InputMethod"]),
  HumanoidRigType: new Set(["R6", "R15"]),
  RenderPriority: new Set(["First", "Input", "Camera", "Character", "Last"]),
  LightType: new Set(["Point", "Spot", "Surface"]),
  CollisionFidelity: new Set(["Default", "Hull", "Box", "PreciseConvexDecomposition"]),
  Technology: new Set(["Legacy", "Voxel", "Compatibility", "ShadowMap", "Future"]),
  TextXAlignment: new Set(["Left", "Center", "Right"]),
  TextYAlignment: new Set(["Top", "Center", "Bottom"]),
  FillDirection: new Set(["Horizontal", "Vertical"]),
  HorizontalAlignment: new Set(["Left", "Center", "Right"]),
  VerticalAlignment: new Set(["Top", "Center", "Bottom"]),
  EasingStyle: new Set(["Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce",
    "Elastic", "Exponential", "Circular", "Cubic"]),
  EasingDirection: new Set(["In", "Out", "InOut"]),
  SortOrder: new Set(["LayoutOrder", "Name", "Custom"]),
  SizeConstraint: new Set(["RelativeXY", "RelativeXX", "RelativeYY"]),
  ContextActionPriority: new Set(["Low", "Medium", "High"]),
};

// Veri tipi kurucuları / statik üyeler
const DATATYPE_MEMBERS = {
  Vector3: new Set(["new", "zero", "one", "xAxis", "yAxis", "zAxis", "Lerp", "Dot", "Cross",
    "Normalize", "AngleBetween"]),
  Vector2: new Set(["new", "zero", "one", "xAxis", "yAxis", "Lerp", "Dot", "Cross"]),
  CFrame: new Set(["new", "identity", "Angles", "lookAt", "fromEulerAnglesXYZ",
    "fromEulerAnglesYXZ", "fromMatrix", "fromAxisAngle", "fromOrientation", "fromScale"]),
  Color3: new Set(["new", "fromRGB", "fromHSV", "fromHex", "toHex", "Lerp"]),
  UDim: new Set(["new", "fromScale", "fromOffset"]),
  UDim2: new Set(["new", "fromScale", "fromOffset"]),
  NumberSequence: new Set(["new"]),
  NumberSequenceKeypoint: new Set(["new"]),
  ColorSequence: new Set(["new"]),
  ColorSequenceKeypoint: new Set(["new"]),
  NumberRange: new Set(["new"]),
  BrickColor: new Set(["new", "random", "White", "Black", "DarkGray", "Gray", "Red", "Green", "Blue", "Yellow"]),
  Rect: new Set(["new"]),
  Ray: new Set(["new"]),
  Region3: new Set(["new"]),
  PhysicalProperties: new Set(["new"]),
  TweenInfo: new Set(["new"]),
  Axes: new Set(["new"]),
  Faces: new Set(["new"]),
  Random: new Set(["new"]),
  PathWaypoint: new Set(["new"]),
  RaycastParams: new Set(["new"]),
  OverlapParams: new Set(["new"]),
  Font: new Set(["new", "fromEnum", "fromName"]),
  Instance: new Set(["new"]),
  DateTime: new Set(["now", "fromUnixTimestamp", "fromLocalTime", "fromUniversalTime"]),
  Enum: new Set(Object.keys(ROBLOX_ENUMS)),
};

// Roblox özellik/olay adları (PascalCase üye erişimleri bu listede olmalı)
const ROBLOX_MEMBERS = new Set([
  // Instance çekirdeği
  "Parent", "Name", "ClassName", "AncestryChanged", "Changed", "ChildAdded", "ChildRemoved",
  "Destroying", "AttributeChanged", "GetAttribute", "SetAttribute", "Archivable",
  // Script容器
  "Source", "Enabled", "RunContext", "LinkedSource", "CurrentEditor",
  // BasePart
  "CFrame", "Size", "Position", "Rotation", "Orientation", "Color", "Material",
  "Transparency", "Anchored", "CanCollide", "CanTouch", "CanQuery", "CastShadow",
  "TopSurface", "BottomSurface", "Shape", "Massless", "LocalTransparencyModifier",
  "Reflectance", "Velocity", "RotVelocity", "AssemblyLinearVelocity",
  "AssemblyAngularVelocity", "AssemblyMass", "AssemblyCenterOfMass", "BrickColor",
  "CollisionGroup", "CollisionFidelity", "CustomPhysicalProperties", "RootPriority",
  "MaterialVariant", "SurfaceOrientation",
  // Model
  "PrimaryPart", "LevelOfDetail", "Scale", "WorldPivot",
  // Humanoid
  "Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "Jump",
  "PlatformStand", "RigType", "RootPart", "MoveDirection", "State", "StateChanged",
  "Died", "HealthChanged", "AutoRotate", "AutoJumpEnabled", "DisplayName",
  "EvaluateStateMachine", "BreakJointsOnDeath", "HipHeight", "NameOcclusion",
  // Player
  "Character", "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded",
  "PlayerGui", "Backpack", "UserId", "Team", "TeamColor", "Leaderstats",
  "ReplicationFocus", "CameraMode", "CameraMinZoomDistance", "CameraMaxZoomDistance",
  "DevEnableMouseLock", "DevComputerMovementMode", "DevTouchMovementMode",
  // Kamera
  "CameraType", "CameraSubject", "CurrentCamera", "FieldOfView", "Focus", "LookVector",
  "RightVector", "UpVector", "NearPlaneZ", "DiagonalFieldOfView",
  // Workspace / Lighting
  "Gravity", "FilteringEnabled", "ClientAnimatorThrottling", "StreamingEnabled",
  "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "EnvironmentDiffuseScale",
  "EnvironmentSpecularScale", "GlobalShadows", "ExposureCompensation", "FogStart",
  "FogEnd", "FogColor", "Technology", "ShadowSoftness", "ShadowColor", "GeographicLatitude",
  // Atmosphere
  "Density", "Offset", "Color", "Decay", "Glare", "Haze",
  // Gui
  "Text", "TextColor3", "TextSize", "TextScaled", "TextWrapped", "TextTransparency",
  "TextXAlignment", "TextYAlignment", "Font", "FontFace", "BackgroundColor3",
  "BackgroundTransparency", "BorderSizePixel", "BorderColor3", "BorderMode", "AnchorPoint",
  "Visible", "ZIndex", "LayoutOrder", "ClipsDescendants", "Active", "AutoButtonColor",
  "CornerRadius", "SizeConstraint", "ResetOnSpawn", "IgnoreGuiInset", "DisplayOrder",
  "FillDirection", "HorizontalAlignment", "VerticalAlignment", "Selectable",
  "AutomaticSize", "RichText", "MaxVisibleGraphemes", "LineHeight", "PlaceholderText",
  "ClearTextOnFocus", "MultiLine", "ScrollBarThickness", "ScrollingEnabled",
  "Scale", "Offset", "MouseButton1Click", "Activated", "MouseEnter", "MouseLeave",
  // Trail / Attachment / Beam / ParticleEmitter
  "Attachment0", "Attachment1", "Lifetime", "WidthScale", "Transparency", "LightEmission",
  "LightInfluence", "Speed", "Rate", "Texture", "TextureLength", "TextureMode",
  "FaceCamera", "ZOffset", "Axis", "SecondaryAxis", "WorldPosition", "WorldAxis",
  "WorldCFrame", "WorldOrientation", "WorldSecondaryAxis",
  // Remote / sinyal
  "OnServerEvent", "OnClientEvent", "OnServerInvoke", "OnClientInvoke", "Value",
  "ObjectValue", "Heartbeat", "RenderStepped", "Stepped", "InputBegan", "InputEnded",
  "InputChanged", "TouchEnabled", "GamepadEnabled", "KeyboardEnabled", "MouseBehavior",
  "MouseIconEnabled", "PlayerAdded", "PlayerRemoving", "LocalPlayer", "Players",
  // Motor6D
  "Transform", "C0", "C1", "Part0", "Part1", "DesiredAngle",
  // RunService / ContextActionService
  "IsServer", "IsClient", "IsStudio", "IsRunMode", "FrameRateManager",
  // Vector/Color bileşenleri
  "X", "Y", "Z", "R", "G", "B", "H", "S", "V", "Magnitude", "Unit", "Keypoints",
  "Time", "Envelope", "Min", "Max", "KeyCode", "UserInputType", "Position", "Delta",
  "Processed", "TargetPoint", "UserId", "Origin", "Direction", "ViewportSize", "FieldOfView",
  "Intensity", "Spread", "Threshold", "Saturation", "TintColor", "Contrast", "SkyboxBloom",
  // Spawn / Tool
  "AllowTeamChangeOnTouch", "Neutral", "Duration", "AllowGlideOnTouch", "SpawnPoint",
  "RequiresHandle", "Handle", "Grip", "ToolTip", "Activated", "Deactivated", "Equipped",
]);

// Roblox API metotları (PascalCase `:Metot(` çağrıları)
const ROBLOX_METHODS = new Set([
  "GetService", "FindFirstChild", "FindFirstChildOfClass", "FindFirstChildWhichIsA",
  "FindFirstAncestor", "FindFirstAncestorOfClass", "FindFirstChildWhichIsAClass",
  "WaitForChild", "GetChildren", "GetDescendants", "GetFullName", "GetRootPart",
  "GetPropertyChangedSignal", "IsA", "IsAncestorOf", "IsDescendantOf", "Clone", "Destroy",
  "ClearAllChildren", "Connect", "ConnectParallel", "Once", "Wait", "Disconnect", "Fire",
  "FireServer", "FireClient", "FireAllClients", "InvokeServer", "InvokeClient", "InvokeAsync",
  "GetPlayers", "GetPlayerFromCharacter", "GetPlayerByUserId", "GetPlayerById",
  "SetStateEnabled", "GetStateEnabled", "ChangeState", "GetState", "MoveTo", "Jump",
  "GetMass", "GetJoints", "GetTouchingParts", "GetNetworkOwner", "SetNetworkOwner",
  "SetPrimaryPartCFrame", "GetPrimaryPartCFrame", "PivotTo", "GetPivot", "MoveTo",
  "ScaleTo", "GetBoundingBox", "GetExtentsSize", "BreakJoints", "ApplyImpulse",
  "ApplyAngularImpulse", "AddForce", "GetVelocityAtPosition", "Raycast",
  "GetPartBoundsInBox", "GetPartBoundsInRadius", "FindPartOnRay", "FindPartOnRayWithIgnoreList",
  "TweenSize", "TweenPosition", "Play", "Stop", "Pause", "Resume", "LoadAnimation",
  "BindAction", "UnbindAction", "BindActionAtPriority", "UnbindAllActions",
  "GetString", "SetCore", "SetCoreGuiEnabled", "AddItem", "SendNotification",
  "Lerp", "Inverse", "ToWorldSpace", "ToObjectSpace", "PointToWorldSpace",
  "VectorToWorldSpace", "VectorToObjectSpace", "GetComponents", "LookAt", "TranslateBy",
  "Rotate", "Equals", "FuzzyEq", "Dot", "Cross", "AngleBetween", "Normalize",
  "GetAttribute", "SetAttribute", "GetAttributes", "RequestCharacter", "LoadCharacter",
  "Kick", "GetRankInGroup", "IsInGroup", "SetCoreGuiEnabled", "EnableResetOnSpawn",
  "GetActor", "GetDebugId", "GetDebugStats", "SetAttribute", "GetAttributeChangedSignal",
  "GetMouseLocation", "ViewportPointToRay", "ViewportSize", "GetRenderFPS", "GetTheta",
  "WaitForChild", "AddPlayerToTeam", "CreateCharacter", "ResetCharacter",
]);

// Roblox globalleri (motor kodunda çıplak isim olarak kullanılabilir)
const ROBLOX_GLOBALS = new Set([
  "game", "workspace", "Instance", "Vector3", "Vector2", "CFrame", "Color3", "UDim",
  "UDim2", "Enum", "NumberSequence", "NumberSequenceKeypoint", "ColorSequence",
  "ColorSequenceKeypoint", "NumberRange", "BrickColor", "PhysicalProperties", "Ray",
  "Region3", "Rect", "TweenInfo", "Random", "Axes", "Faces", "DateTime", "Font",
  "PathWaypoint", "RaycastParams", "OverlapParams", "warn", "tick", "wait", "spawn",
  "delay", "typeof", "settings", "UserSettings", "plugin", "shared", "script", "task",
  "DebuggerManager", "elapsedTime", "time",
]);

const LUA_BUILTINS = new Set([
  "print", "require", "pcall", "xpcall", "error", "assert", "tostring", "tonumber",
  "type", "pairs", "ipairs", "next", "select", "setmetatable", "getmetatable",
  "rawget", "rawset", "rawlen", "rawequal", "unpack", "table", "string", "math",
  "os", "coroutine", "load", "loadstring", "utf8", "bit32", "_G", "_VERSION",
]);

// Yalnızca istemci tarafında anlamlı olan API
const CLIENT_ONLY = [
  "Players.LocalPlayer", "LocalPlayer", "Workspace.CurrentCamera", "CurrentCamera",
  "UserInputService", "ContextActionService", "RenderStepped", "StarterGui",
  "PlayerGui", "LocalTransparencyModifier", "OnClientEvent", "InvokeServer",
  "FireServer", "MouseBehavior", "GuiService", "StarterPlayerScripts", "TweenService",
];

// Yalnızca sunucu tarafında anlamlı olan API
const SERVER_ONLY = [
  "OnServerEvent", "FireClient", "FireAllClients", "InvokeClient", "ServerScriptService",
  "ServerStorage", "SetNetworkOwner", "GetPlayers", "AddPlayerToTeam", "DataStoreService",
  "HttpService", "MessagingService", "Kick",
];

/** src/ altındaki tüm modüller (kurulum dosyasının da tek doğruluk kaynağı). */
const modules = installerLib.collectModules();

/* ------------------------------------------------- modül API sözleşmesi yardımcıları */

const byKey = new Map(modules.map((m) => [m.key, m]));

/** Dosya yolundan modül anahtarı: "src/shared/Core/Vec3.luau" -> "shared/Core/Vec3" */
function keyOfFile(file) {
  const r = path.relative(SRC, file).split(path.sep).join("/");
  return r.replace(/\.(server|client)\.luau$/, "").replace(/\.luau$/, "");
}

/** `require(...)` argümanını modül anahtarına çözer (çözülemiyorsa null). */
function resolveRequire(expr, ownKey) {
  const e = expr.trim();
  // require(Shared.Core.Vec3) -> shared/Core/Vec3
  const shared = e.match(/^Shared(?:\.([A-Za-z0-9_]+))*$/);
  if (shared) return "shared/" + e.split(".").slice(1).join("/");
  if (!ownKey) return null;
  const ownParts = ownKey.split("/");
  // require(script.Parent[.Parent...][.X.Y])
  const m = e.match(/^script\.Parent((?:\.Parent)*)((?:\.[A-Za-z0-9_]+)*)$/);
  if (!m) return null;
  const ups = (m[1].match(/Parent/g) || []).length + 1; // script.Parent = kendi klasörü
  const base = ownParts.slice(0, Math.max(0, ownParts.length - ups));
  const tail = m[2] ? m[2].split(".").filter(Boolean) : [];
  const key = base.concat(tail).join("/");
  return key || null;
}

/** Bir modülün dışa aktardığı fonksiyon/metot adları. */
function exportedFunctions(source) {
  const code = maskLua(source);
  const names = new Set();
  for (const m of code.matchAll(/function\s+[A-Za-z0-9_]+\s*[.:]\s*([A-Za-z0-9_]+)\s*\(/g)) names.add(m[1]);
  for (const m of code.matchAll(/[A-Za-z0-9_]+\s*[.:]\s*([A-Za-z0-9_]+)\s*=\s*function/g)) names.add(m[1]);
  // return { ad = ..., } biçimindeki tablolar
  const retIdx = code.lastIndexOf("return");
  if (retIdx !== -1) {
    const tail = code.slice(retIdx, retIdx + 2000);
    if (/return\s*\{/.test(tail)) {
      for (const m of tail.matchAll(/([A-Za-z0-9_]+)\s*=/g)) names.add(m[1]);
    }
  }
  return names;
}

const EXPORTS = new Map(modules.map((m) => [m.key, exportedFunctions(m.source)]));

/* ------------------------------------------------------------------ kapı çerçevesi */

/**
 * VERIFY_ONLY=api,remote  → yalnızca bu kapılar koşar (hızlı yineleme için).
 * Boşsa hepsi koşar. Atlanan kapılar raporda "ATLANDI" görünür ve sonucu
 * etkilemez; ama SONUÇ satırında kaç kapının atlandığı açıkça yazılır.
 */
const ONLY = (process.env.VERIFY_ONLY || "")
  .split(",")
  .map((x) => x.trim())
  .filter(Boolean);
const enabled = (id) => ONLY.length === 0 || ONLY.includes(id);

const results = [];
let gateIndex = 0;

function gate(id, title, fn) {
  gateIndex++;
  if (!enabled(id)) {
    results.push({ id, title, ok: true, skipped: true, errors: [], warnings: [], info: [] });
    return true;
  }
  const bag = { errors: [], warnings: [], info: [] };
  const api = {
    error: (m) => bag.errors.push(m),
    warn: (m) => bag.warnings.push(m),
    note: (m) => bag.info.push(m),
  };
  let crashed = null;
  try {
    fn(api);
  } catch (e) {
    crashed = e && e.stack ? e.stack.split("\n").slice(0, 3).join(" | ") : String(e);
  }
  const ok = crashed === null && bag.errors.length === 0;
  results.push({ id, title, ok, crashed, ...bag });
  return ok;
}

/* =================================================================== 1) ORTAM */

gate("ortam", "Ortam: Node + Lua VM", (g) => {
  const major = parseInt(process.versions.node.split(".")[0], 10);
  if (major < 18) g.error("Node >= 18 gerekli, bulunan " + process.versions.node);
  else g.note("node v" + process.versions.node);

  if (!fs.existsSync(FENGARI)) {
    g.error("Lua VM bulunamadı: " + rel(FENGARI) + " — çalıştır: npm install");
    return;
  }
  fs.mkdirSync(BUILD, { recursive: true });
  const probe = path.join(BUILD, "verify_probe.lua");
  fs.writeFileSync(probe, 'print("PROBE_OK " .. tostring(math.floor(1.5)))\n');
  const r = runFengari(probe);
  if (!r.ok || !/PROBE_OK 1/.test(r.stdout)) {
    g.error("Lua VM çalışmıyor: " + (r.stderr || r.stdout || "çıktı yok").slice(0, 200));
  } else {
    g.note("fengari (Lua 5.3) çalışıyor");
  }

  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8"));
  for (const name of ["test", "trace", "anim", "preview", "install:build", "verify"]) {
    if (!pkg.scripts || !pkg.scripts[name]) g.error("package.json içinde '" + name + "' script'i yok");
  }
  g.note(Object.keys(pkg.scripts).length + " npm script tanımlı");
});

/* ============================================================== 2) SÖZDİZİMİ */


gate("sozdizimi", "Sözdizimi: Roblox'a giden her dosya derleniyor", (g) => {
  const installerText = installerLib.readInstaller();
  if (installerText === null) {
    g.error("install/FootballSim_Install.lua yok — çalıştır: npm run install:build");
  }
  const bootstrap = fs.readFileSync(path.join(ROOT, "tools", "installer", "bootstrap.lua"), "utf8");

  fs.mkdirSync(BUILD, { recursive: true });
  const parts = [];
  parts.push("-- OTOMATIK URETILDI: tools/verify.js (sozdizimi denetimi)");
  parts.push("local SOURCES = {");
  for (const m of modules) parts.push("  [" + luaString(m.key) + "] = " + luaString(m.source) + ",");
  parts.push("};");
  parts.push("local BOOTSTRAP = " + luaString(bootstrap));
  parts.push("local INSTALLER = " + luaString(installerText || ""));
  parts.push(`
local bad, count = {}, 0
for name, src in pairs(SOURCES) do
  count = count + 1
  local chunk, err = load(src, "@" .. name)
  if not chunk then bad[#bad + 1] = "MODUL " .. name .. ": " .. tostring(err) end
end
do
  local chunk, err = load(BOOTSTRAP, "@bootstrap")
  count = count + 1
  if not chunk then bad[#bad + 1] = "MODUL tools/installer/bootstrap.lua: " .. tostring(err) end
end
do
  local chunk, err = load(INSTALLER, "@FootballSim_Install")
  count = count + 1
  if not chunk then bad[#bad + 1] = "MODUL install/FootballSim_Install.lua: " .. tostring(err) end
end
for _, line in ipairs(bad) do print("HATA " .. line) end
print("SYNTAX_SUMMARY " .. tostring(count) .. " " .. tostring(#bad))
`);
  const bundle = path.join(BUILD, "verify_syntax.lua");
  fs.writeFileSync(bundle, parts.join("\n"));

  const r = runFengari(bundle);
  const out = r.stdout + r.stderr;
  for (const line of out.split("\n")) {
    if (line.startsWith("HATA ")) g.error(line.slice(5).trim());
  }
  const m = out.match(/SYNTAX_SUMMARY (\d+) (\d+)/);
  if (!m) g.error("sözdizimi denetimi hiç çalışmadı (Lua VM çıktısı yok): " + out.slice(0, 300));
  else g.note(m[1] + " kaynak derlendi, " + m[2] + " sözdizimi hatası");

  // JSON dosyaları
  for (const f of ["package.json", "default.project.json", "package-lock.json"]) {
    const p = path.join(ROOT, f);
    if (!fs.existsSync(p)) {
      g.error(f + " yok");
      continue;
    }
    try {
      JSON.parse(fs.readFileSync(p, "utf8"));
    } catch (e) {
      g.error(f + " geçersiz JSON: " + e.message);
    }
  }
});

/* ============================================================ 3) DİL UYUMU */

const FORBIDDEN_API = [
  { re: /\bio\s*\.\s*\w+/g, why: "Roblox sandbox'ında io kütüphanesi yok" },
  { re: /\bos\s*\.\s*(?!clock|time|date|difftime)\w+/g, why: "Roblox'ta os.<bu> yok (os.clock/time/date/difftime var)" },
  { re: /\bdebug\s*\.\s*\w+/g, why: "Roblox sandbox'ında debug kütüphanesi yok" },
  { re: /\bpackage\s*\.\s*\w+/g, why: "Roblox'ta package kütüphanesi yok" },
  { re: /\b(loadfile|dofile|loadstring|string\.dump|newproxy|collectgarbage)\s*\(/g, why: "Roblox'ta bu fonksiyon yok/kapalı" },
  { re: /\bgoto\b/g, why: "Luau'da goto yok" },
  { re: /(?<![~<>=!\/])\/\/(?![*=])/g, why: "Luau'da tam sayı bölmesi (//) yok" },
  { re: /<<|>>/g, why: "Luau'da bit kaydırma operatörü yok (bit32 kullan)" },
  { re: /(?<![~\w])~(?!=)/g, why: "Luau'da bitsel ~ operatörü yok (~= hariç)" },
  { re: /(?<![|])\|(?!\|)(?!=)/g, why: "Luau'da bitsel | operatörü yok" },
  { re: /(?<![&\w])&(?!&)(?!=)/g, why: "Luau'da bitsel & operatörü yok" },
  { re: /<\s*(close|const)\s*>/g, why: "Luau'da <close>/<const> niteliği yok" },
  { re: /\bcontinue\b/g, why: "Luau'da `continue` yok; test koşucusu da (Lua 5.3) derleyemez" },
  { re: /\w\s*(\+=|-=|\*=|\/=|%=|\^=|\.\.=)/g, why: "Luau bileşik ataması (+= vb.) test koşucusunda (Lua 5.3) derlenemez" },
];

gate("dil", "Dil uyumu: Roblox Luau'da çalışmayacak sözdizimi/API yok", (g) => {
  let checked = 0;
  for (const file of shippedFiles()) {
    const raw = fs.readFileSync(file, "utf8");
    const code = stripLua(raw);
    checked++;
    for (const rule of FORBIDDEN_API) {
      rule.re.lastIndex = 0;
      let m;
      while ((m = rule.re.exec(code)) !== null) {
        g.error(rel(file) + ":" + lineOf(code, m.index) + " → " + JSON.stringify(m[0].trim()) + " — " + rule.why);
      }
    }
    // Luau tip notasyonu: fengari (Lua 5.3) derleyemez -> test kapsamı dışında kalır
    const typeAnn = /(local\s+\w+\s*:\s*[A-Za-z_])|(export\s+type\s)|(^\s*type\s+\w+\s*=)/gm;
    let tm;
    while ((tm = typeAnn.exec(code)) !== null) {
      g.warn(rel(file) + ":" + lineOf(code, tm.index) + " → Luau tip notasyonu; test koşucusu Lua 5.3 kullandığı için bu dosya test edilemez");
    }
  }
  g.note(checked + " Roblox dosyası tarandı (yorum/string'ler elenerek)");
});

/* ================================================================ 4) ROBLOX API */

gate("api", "Roblox API yüzeyi: servis / sınıf / Enum / özellik / metot", (g) => {
  // Modül ve klasör adları (script.Parent.X erişimleri) otomatik olarak serbest
  const moduleNames = new Set();
  for (const m of modules) {
    for (const seg of m.key.split("/")) moduleNames.add(seg);
  }
  // Roblox'ta klasor adlari buyuk harfle baslar (ReplicatedStorage.Shared),
  // src/ yollari ise kucuk harfli (src/shared): ikisini de kabul et.
  for (const seg of [...moduleNames]) {
    moduleNames.add(seg.charAt(0).toUpperCase() + seg.slice(1));
    moduleNames.add(seg.toLowerCase());
  }
  moduleNames.add("Shared");
  moduleNames.add("Server");
  moduleNames.add("Client");
  // Metot adları DEĞER olarak da erişilebilir (`type(inst.FindFirstChild)`,
  //回调 olarak geçirme); bu yüzden üye listesi metot adlarını da kapsar.
  // Yazım hatası yapan bir ÇAĞRI yine yakalanır: `:Metot(` denetimi ayrıdır.
  const memberAllow = new Set([...ROBLOX_MEMBERS, ...ROBLOX_METHODS, ...moduleNames]);
  for (const members of Object.values(DATATYPE_MEMBERS)) for (const x of members) memberAllow.add(x);
  for (const items of Object.values(ROBLOX_ENUMS)) for (const x of items) memberAllow.add(x);

  const mockSrc = fs.readFileSync(path.join(ROOT, "tools", "roblox_mock.luau"), "utf8");
  const mockGlobals = new Set([...mockSrc.matchAll(/set\("([A-Za-z0-9_]+)"/g)].map((m) => m[1]));

  let services = 0, classes = 0, enums = 0, members = 0, methods = 0;

  for (const file of shippedFiles()) {
    const raw = fs.readFileSync(file, "utf8");
    // `code`: yorum VE string gövdeleri elenir → üye/metot taraması string içine takılmaz.
    // `codeStr`: yalnızca yorumlar elenir, string sabitleri DURUR → GetService("X") ve
    // Instance.new("X") gibi adı string'den alan çağrılar burada aranır.
    const code = stripLua(raw);
    const codeStr = maskLua(raw);
    const where = (idx) => rel(file) + ":" + lineOf(codeStr, idx);

    // 1) GetService("X")
    for (const m of codeStr.matchAll(/GetService\s*\(\s*"([A-Za-z0-9_]+)"\s*\)/g)) {
      services++;
      if (!ROBLOX_SERVICES.has(m[1])) g.error(where(m.index) + " → bilinmeyen servis: " + m[1]);
    }

    // 2) Instance.new("X")
    for (const m of codeStr.matchAll(/Instance\s*\.\s*new\s*\(\s*"([A-Za-z0-9_]+)"/g)) {
      classes++;
      if (!ROBLOX_CLASSES.has(m[1])) g.error(where(m.index) + " → Instance.new ile bilinmeyen sınıf: " + m[1]);
    }

    // 3) Enum.Kategori.Oge
    for (const m of code.matchAll(/Enum\s*\.\s*([A-Za-z0-9_]+)\s*\.\s*([A-Za-z0-9_]+)/g)) {
      enums++;
      const cat = ROBLOX_ENUMS[m[1]];
      if (!cat) g.error(where(m.index) + " → bilinmeyen Enum kategorisi: " + m[1]);
      else if (!cat.has(m[2])) g.error(where(m.index) + " → Enum." + m[1] + " içinde '" + m[2] + "' yok (yazım hatası?)");
    }

    // 4) Veri tipi üyeleri: Vector3.new / CFrame.lookAt / Color3.fromRGB ...
    for (const dt of Object.keys(DATATYPE_MEMBERS)) {
      const re = new RegExp("(?<![A-Za-z0-9_.])" + dt + "\\s*\\.\\s*([A-Za-z0-9_]+)", "g");
      for (const m of code.matchAll(re)) {
        members++;
        if (!DATATYPE_MEMBERS[dt].has(m[1])) {
          g.error(where(m.index) + " → " + dt + "." + m[1] + " Roblox'ta yok");
        }
      }
    }

    // 5) :Metot( — PascalCase olanlar Roblox API'sidir
    for (const m of code.matchAll(/:\s*([A-Z][A-Za-z0-9_]*)\s*\(/g)) {
      methods++;
      if (!ROBLOX_METHODS.has(m[1])) {
        g.error(where(m.index) + " → bilinmeyen Roblox metodu: :" + m[1] + "()");
      }
    }

    // 6) .Uye — PascalCase olanlar Roblox özelliği/olayı olmalı
    for (const m of code.matchAll(/\.\s*([A-Z][A-Za-z0-9_]*)/g)) {
      const name = m[1];
      // TAMAMI BÜYÜK HARF olanlar motor sabitleridir (Config.GRAVITY, KickAnim.CONTACT_TIME);
      // Roblox özellikleri daima PascalCase'tir, bu yüzden bu biçim güvenle atlanır.
      if (/^[A-Z0-9_]+$/.test(name)) continue;
      // Enum.Kategori / Enum.Kategori.Oge yukarıda denetlendi
      const before = code.slice(Math.max(0, m.index - 60), m.index);
      if (/Enum\s*\.\s*[A-Za-z0-9_]*$/.test(before)) continue;
      if (/Enum\s*\.\s*[A-Za-z0-9_]+\s*\.\s*[A-Za-z0-9_]*$/.test(before)) continue;
      // Veri tipi üyeleri yukarıda denetlendi
      if (new RegExp("(?<![A-Za-z0-9_.])(?:" + Object.keys(DATATYPE_MEMBERS).join("|") + ")\\s*\\.\\s*$").test(before)) continue;
      members++;
      if (!memberAllow.has(name)) {
        g.error(where(m.index) + " → bilinmeyen Roblox özelliği/olayı: ." + name);
      }
    }

    // 7) Modül API sözleşmesi: require edilen modülün OLMAYAN üyesi çağrılıyor mu?
    //    ("attempt to call a nil value" sınıfı — yalnızca çalışma zamanında patlar)
    const ownKey = file.startsWith(SRC) ? keyOfFile(file) : null;
    const bindings = new Map();
    for (const m of codeStr.matchAll(/local\s+([A-Za-z0-9_]+)\s*=\s*require\s*\(([^)]*)\)/g)) {
      const target = resolveRequire(m[2], ownKey);
      if (target && EXPORTS.has(target)) bindings.set(m[1], target);
      else if (target && !EXPORTS.has(target) && !/^shim|__load/.test(m[2])) {
        g.error(where(m.index) + " → require(" + m[2].trim() + ") çözümlenemiyor: src/'de '" + target + "' modülü yok");
      }
    }
    for (const [varName, targetKey] of bindings) {
      const available = EXPORTS.get(targetKey);
      if (!available || available.size === 0) continue;
      const callRe = new RegExp("(?<![A-Za-z0-9_.])" + varName + "\\s*[.:]\\s*([A-Za-z0-9_]+)\\s*\\(", "g");
      for (const m of codeStr.matchAll(callRe)) {
        if (!available.has(m[1])) {
          g.error(where(m.index) + " → " + varName + "." + m[1] + "() çağrılıyor ama " + targetKey + " bunu dışa aktarmıyor (çalışma zamanında 'call a nil value')");
        }
      }
    }

    // 8) Roblox globalleri test ortamında (mock) var mı?
    for (const name of ROBLOX_GLOBALS) {
      const re = new RegExp("(?<![.:A-Za-z0-9_])" + name + "(?![A-Za-z0-9_])", "g");
      let hit = null;
      for (const m of code.matchAll(re)) {
        hit = m;
        break;
      }
      if (!hit) continue;
      // Dosya kendi içinde bu adı tanımlıyorsa (local spawn, function Sim:tick) atla
      const declared = new RegExp("(local\\s+[\\w,\\s]*\\b" + name + "\\b)|(function\\s+[\\w.:]*\\b" + name + "\\b)|(function\\s*\\([^)]*\\b" + name + "\\b)").test(code);
      if (declared) continue;
      // Atama ya da tablo anahtarı (state.time = 0, {time = 1}) → global kullanım değil
      if (/^\s*=(?!=)/.test(code.slice(hit.index + name.length, hit.index + name.length + 4))) continue;
      // Fonksiyon parametresi (function Sample(speed, phase, time)) → global kullanım değil
      if (new RegExp("function\\s+[\\w.:]*\\s*\\([^)]*\\b" + name + "\\b").test(code)) continue;
      // Parametre listesi içinde mi?
      const paramList = /function[\s\w.:]*\(([^)]*)\)/g;
      let inParams = false, pm;
      while ((pm = paramList.exec(code)) !== null) {
        if (pm.index <= hit.index && hit.index < pm.index + pm[0].length && new RegExp("\\b" + name + "\\b").test(pm[1])) {
          inParams = true;
          break;
        }
      }
      if (inParams) continue;
      if (LUA_BUILTINS.has(name)) continue;
      if (name === "script" || name === "shared" || name === "print" || name === "warn") continue;
      if (!mockGlobals.has(name)) {
        g.warn(rel(file) + " → Roblox global '" + name + "' kullanılıyor ama sahte ortam (tools/roblox_mock.luau) sağlamıyor; testte bu yol çalışmaz");
      }
    }
  }
  g.note(services + " servis, " + classes + " Instance.new sınıfı, " + enums + " Enum öğesi, " + methods + " Roblox metodu, " + members + " özellik/veri tipi üyesi doğrulandı");
  g.note(EXPORTS.size + " modülün dışa aktardığı API, " + modules.length + " require bağlamasında çapraz denetlendi");
});

/* ================================================================= 5) SINIR */

gate("sinir", "Sınır: sunucu / istemci / paylaşılan dosyalar doğru tarafta", (g) => {
  const serverFiles = modules.filter((m) => m.key.startsWith("server/"));
  const clientFiles = modules.filter((m) => m.key.startsWith("client/"));
  const sharedFiles = modules.filter((m) => m.key.startsWith("shared/"));

  if (serverFiles.length === 0) g.error("src/server altında hiç dosya yok");
  if (clientFiles.length === 0) g.error("src/client altında hiç dosya yok");
  if (sharedFiles.length === 0) g.error("src/shared altında hiç dosya yok");

  const scan = (list, forbidden, side) => {
    for (const m of list) {
      const code = stripLua(m.source);
      for (const token of forbidden) {
        const needle = token.includes(".") ? token.split(".").pop() : token;
        const re = new RegExp("(?<![A-Za-z0-9_])" + needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(?![A-Za-z0-9_])");
        const hit = re.exec(code);
        if (hit) {
          g.error(m.key + ":" + lineOf(code, hit.index) + " → " + side + " dosyasında " + token + " kullanılamaz (" + needle + ")");
        }
      }
    }
  };

  scan(serverFiles, CLIENT_ONLY, "sunucu");
  scan(clientFiles, SERVER_ONLY, "istemci");
  scan(sharedFiles, [...CLIENT_ONLY.filter((x) => !x.includes(".")), ...SERVER_ONLY], "paylaşılan");

  // Kullanılmayan servis importları (ölü entegrasyon)
  for (const m of modules) {
    const code = stripLua(m.source);
    for (const im of code.matchAll(/local\s+([A-Za-z0-9_]+)\s*=\s*game:GetService\s*\(\s*"([A-Za-z0-9_]+)"\s*\)/g)) {
      const varName = im[1];
      const uses = [...code.matchAll(new RegExp("(?<![A-Za-z0-9_.])" + varName + "(?![A-Za-z0-9_])", "g"))];
      if (uses.length <= 1) {
        g.error(m.key + ":" + lineOf(code, im.index) + " → GetService(\"" + im[2] + ") alınıp hiç kullanılmıyor (ölü entegrasyon)");
      }
    }
  }
  g.note(serverFiles.length + " sunucu, " + clientFiles.length + " istemci, " + sharedFiles.length + " paylaşılan modül denetlendi");
});

/* ============================================================== 6) KURULUM */

gate("kurulum", "Tek kurulum dosyası: kaynaklarla bit-bit senkron", (g) => {
  const fresh = installerLib.generateInstaller().text;
  const onDisk = installerLib.readInstaller();
  if (onDisk === null) {
    g.error("install/FootballSim_Install.lua yok — çalıştır: npm run install:build");
    return;
  }
  if (onDisk !== fresh) {
    g.error("install/FootballSim_Install.lua kaynaklarla SENKRON DEĞİL — çalıştır: npm run install:build");
  } else {
    g.note("senkron (" + (Buffer.byteLength(onDisk) / 1024).toFixed(1) + " KB)");
  }

  // Her modülün kurulum dosyasındaki birebir satır bloğu (üretimle aynı fonksiyon)
  const byKey = new Map(modules.map((m) => [m.key, m]));
  let mismatched = 0;
  for (const mod of modules) {
    if (!onDisk.includes(installerLib.moduleEntry(mod))) {
      g.error(mod.key + " kurulum dosyasına birebir gömülmemiş (kaynak ya da sınıf farklı)");
      mismatched++;
    }
  }
  // Gömülü anahtar/sınıf envanteri: bayat ya da fazla girdi var mı?
  const embedded = new Map();
  for (const m of onDisk.matchAll(/\["([^"]+)"\]\s*=\s*\{\s*class\s*=\s*"([A-Za-z]+)"\s*,\s*source\s*=/g)) {
    embedded.set(m[1], m[2]);
  }
  if (embedded.size === 0) g.error("kurulum dosyasından hiçbir modül çözümlenemedi (biçim değişmiş olabilir)");
  for (const [key, className] of embedded) {
    const mod = byKey.get(key);
    if (!mod) {
      g.error("kurulumdaki '" + key + "' src/'de yok (bayat girdi)");
      mismatched++;
    } else if (mod.className !== className) {
      g.error(key + " sınıfı yanlış: " + className + " (beklenen " + mod.className + ")");
      mismatched++;
    }
  }
  for (const key of byKey.keys()) {
    if (!embedded.has(key)) {
      g.error("src/'deki '" + key + "' kurulum dosyasına gömülmemiş");
      mismatched++;
    }
  }
  if (mismatched === 0) g.note(embedded.size + " modül birebir gömülü (anahtar + sınıf + kaynak)");

  if (!onDisk.includes("FootballSim kurulumu")) g.error("kurulum raporu (bootstrap) dosyada yok");
  const scripts = modules.filter((m) => m.className === "Script").length;
  const locals = modules.filter((m) => m.className === "LocalScript").length;
  const mods = modules.filter((m) => m.className === "ModuleScript").length;
  g.note(mods + " ModuleScript, " + scripts + " Script, " + locals + " LocalScript");
  if (scripts !== 1) g.error("tam 1 sunucu Script'i beklenirdi, bulunan " + scripts);
  if (locals !== 1) g.error("tam 1 istemci LocalScript'i beklenirdi, bulunan " + locals);
});

/* ================================================================== 7) ROJO */

gate("rojo", "Rojo projesi: src/'nin tamamı eşlenmiş", (g) => {
  const p = path.join(ROOT, "default.project.json");
  if (!fs.existsSync(p)) {
    g.error("default.project.json yok");
    return;
  }
  const project = JSON.parse(fs.readFileSync(p, "utf8"));
  if (project.name !== "FootballSim") g.warn("proje adı 'FootballSim' değil: " + project.name);
  if (!project.tree || project.tree.$className !== "DataModel") g.error("tree.$className DataModel olmalı");

  const mapped = [];
  (function visit(node, trail) {
    if (!node || typeof node !== "object") return;
    if (typeof node.$path === "string") {
      mapped.push({ path: node.$path, trail });
      return;
    }
    for (const [key, value] of Object.entries(node)) {
      if (key.startsWith("$")) continue;
      visit(value, trail.concat(key));
    }
  })(project.tree, []);

  if (mapped.length === 0) g.error("projede hiç $path eşlemesi yok");

  const srcDirs = fs.readdirSync(SRC, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
  for (const dir of srcDirs) {
    const hit = mapped.find((m) => m.path === "src/" + dir);
    if (!hit) {
      g.error("src/" + dir + " rojo projesine EŞLENMEMİŞ → `rojo build` bu kodu oyuna taşımaz");
    } else {
      g.note("src/" + dir + " → " + hit.trail.join("/"));
    }
  }
  for (const m of mapped) {
    const full = path.join(ROOT, m.path);
    if (!fs.existsSync(full)) g.error("$path yok: " + m.path);
  }

  // Eşlenmemiş kaynak dosyası kalmasın
  const covered = new Set();
  for (const m of mapped) {
    const abs = path.resolve(ROOT, m.path);
    for (const f of walk(abs, (x) => x.endsWith(".luau"))) covered.add(path.resolve(f));
  }
  for (const f of walk(SRC, (x) => x.endsWith(".luau"))) {
    if (!covered.has(path.resolve(f))) g.error("eşlenmemiş kaynak: " + rel(f));
  }

  // Beklenen yerleşim (kurulum dosyasıyla aynı ağaç)
  const expect = {
    "ReplicatedStorage/Shared": "src/shared",
    "ServerScriptService/Server": "src/server",
    "StarterPlayer/StarterPlayerScripts/Client": "src/client",
  };
  for (const [trail, dir] of Object.entries(expect)) {
    const hit = mapped.find((m) => m.trail.join("/") === trail && m.path === dir);
    if (!hit) g.error("rojo ağacında beklenen eşleme yok: " + trail + " → " + dir);
  }
});

/* ================================================================ 8) REMOTE */

function topLevelArgs(callSource) {
  // callSource: parantez içi metin; derinlik 0'daki virgülleri say
  let depth = 0, args = 1, inStr = null;
  const s = callSource.trim();
  if (s === "") return 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (c === "\\") i++;
      else if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'") { inStr = c; continue; }
    if ("([{".includes(c)) depth++;
    else if (")]}".includes(c)) depth--;
    else if (c === "," && depth === 0) args++;
  }
  return args;
}

function parenContent(src, fromIndex) {
  const open = src.indexOf("(", fromIndex);
  if (open === -1) return null;
  let depth = 0, inStr = null;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (inStr) {
      if (c === "\\") i++;
      else if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'") { inStr = c; continue; }
    if (c === "(") depth++;
    else if (c === ")") {
      depth--;
      if (depth === 0) return src.slice(open + 1, i);
    }
  }
  return null;
}

gate("remote", "Remote sözleşmesi: istemci ↔ sunucu", (g) => {
  const server = modules.find((m) => m.key === "server/SimLoop");
  const client = modules.find((m) => m.key === "client/BallView");
  if (!server || !client) {
    g.error("SimLoop veya BallView bulunamadı");
    return;
  }
  // Remote adları string sabiti olarak geçer: yorumlar elenir ama string'ler KORUNUR.
  const sSrc = maskLua(server.source);
  const cSrc = maskLua(client.source);
  // Remote adları sabit string ya da bir değişken üzerinden kurulabilir (REMOTE_NAMES);
  // bu yüzden kurulum demetinin tamamı taranır.
  const installerText = installerLib.readInstaller() || "";
  const bootstrapSrc = fs.readFileSync(path.join(ROOT, "tools", "installer", "bootstrap.lua"), "utf8");
  const bundle = [installerText, bootstrapSrc, modules.map((m) => m.source).join("\n")].join("\n");

  const EXPECTED_REMOTES = ["Kick", "ResetBall", "MatchState"];

  // Sunucu: remote adları ensureRemote("X") ile (ya da değişken listesiyle) kurulur
  const created = new Set([...sSrc.matchAll(/ensureRemote\s*\(\s*"([^"]+)"\s*\)/g)].map((m) => m[1]));
  for (const name of EXPECTED_REMOTES) {
    if (!created.has(name) && bundle.includes('"' + name + '"')) created.add(name);
  }
  if (created.size === 0) g.error("sunucuda hiçbir remote adı kurulmuyor");

  // İstemci: önce Remotes klasörünü tutan değişken bulunur, sonra yalnızca ONUN
  // çocukları sayılır (Shared/Config/HumanoidRootPart gibi remote olmayanlar elenir)
  const varMatch = cSrc.match(/local\s+([A-Za-z0-9_]+)\s*=\s*ReplicatedStorage:WaitForChild\s*\(\s*"Remotes"/);
  if (!varMatch) {
    g.error("istemci ReplicatedStorage.Remotes klasörünü WaitForChild ile almıyor → remote'lara hiç ulaşamaz");
  }
  const remotesVar = varMatch ? varMatch[1] : null;
  const awaited = remotesVar
    ? new Set([...cSrc.matchAll(new RegExp(remotesVar + "\\s*:\\s*WaitForChild\\s*\\(\\s*\"([^\"]+)\"", "g"))].map((m) => m[1]))
    : new Set();
  if (remotesVar && awaited.size === 0) g.error("istemci '" + remotesVar + "' içinden hiçbir remote beklemiyor");

  for (const name of EXPECTED_REMOTES) {
    if (!created.has(name)) g.error("'" + name + "' remote'u sunucuda kurulmuyor");
    if (!awaited.has(name)) g.error("'" + name + "' remote'unu istemci beklemiyor");
  }
  for (const name of created) {
    if (!awaited.has(name)) g.error("sunucu '" + name + "' remote'unu oluşturuyor ama istemci hiç kullanmıyor (ölü remote)");
  }
  for (const name of awaited) {
    if (!created.has(name)) g.error("istemci '" + name + "' remote'unu bekliyor ama sunucu oluşturmuyor → WaitForChild zaman aşımına düşer");
  }
  g.note([...created].join(", ") + " — sunucu kuruyor, istemci WaitForChild ile alıyor");
  // Remote'lar sunucu scriptinde kurulur (bootstrap yalnızca dosyaları yerleştirir)
  if (!/Instance\.new\s*\(\s*"RemoteEvent"\s*\)/.test(sSrc)) {
    g.error("sunucu Instance.new(\"RemoteEvent\") çağırmıyor → remote'lar hiç oluşmaz");
  }
  if (!/Name\s*=\s*"Remotes"/.test(sSrc)) {
    g.error("sunucu ReplicatedStorage.Remotes klasörünü kurmuyor → istemci WaitForChild(\"Remotes\") takılır");
  }
  if (!/remotes\.Parent\s*=\s*ReplicatedStorage/.test(sSrc)) {
    g.error("Remotes klasörü ReplicatedStorage'a bağlanmıyor");
  }
  if (!/stateRemote:FireAllClients/.test(sSrc)) g.error("sunucu MatchState'i hiç yayınlamıyor (skor istemciye gitmez)");
  if (!/stateRemote\.OnClientEvent:Connect/.test(cSrc)) g.error("istemci MatchState dinlemiyor (HUD güncellenmez)");

  // Sunucu otorite koruması: topa yazılacak HER hız sonluluk denetiminden geçmeli.
  // Bu kural, `if isFiniteVec3(velocity) then` satırının silinmesini yakalar —
  // davranışsal testle görülmez çünkü istemci girdisi zaten finiteNumber/clamp'ten
  // geçiyor; koruma balistik çözücünün NaN ürettiği durumlar için son savunma hattı.
  const GUARD_WINDOW = 700;
  const launchSites = [...sSrc.matchAll(/Ballistics\.solveLaunch\s*\(/g)];
  if (launchSites.length === 0) g.error("sunucuda hiç Ballistics.solveLaunch çağrısı yok (şut uygulanmıyor)");
  let guarded = 0;
  for (const site of launchSites) {
    const after = sSrc.slice(site.index, site.index + GUARD_WINDOW);
    if (/isFiniteVec3\s*\(|Validate\.vec3\s*\(/.test(after)) guarded++;
    else g.error("satır " + lineOf(sSrc, site.index) + " → Ballistics.solveLaunch çıktısı sonluluk denetiminden GEÇMİYOR (isFiniteVec3 yok): NaN hız topun tüm durumunu kalıcı bozar");
  }
  if (guarded > 0) g.note(guarded + "/" + launchSites.length + " launch bölgesi isFiniteVec3 ile korunuyor");

  // Doğrulama mantığı test edilebilir bir paylaşılan modülde mi?
  if (!/require\s*\(\s*Shared\.Core\.Validate\s*\)/.test(sSrc)) {
    g.error("sunucu Shared.Core.Validate modülünü require etmiyor → girdi doğrulama birim testlerinin dışında kalır");
  }
  if (!modules.some((m) => m.key === "shared/Core/Validate")) {
    g.error("src/shared/Core/Validate.luau yok → girdi doğrulama kuralları test edilemez");
  }

  // Kick: FireServer argüman sayısı == OnServerEvent parametre sayısı - 1 (player)
  const fireIdx = cSrc.indexOf("kickRemote:FireServer");
  if (fireIdx === -1) g.error("istemci kickRemote:FireServer çağırmıyor (şut hiç gönderilmez)");
  const handlerIdx = sSrc.indexOf("kickRemote.OnServerEvent:Connect");
  if (handlerIdx === -1) g.error("sunucu kickRemote.OnServerEvent dinlemiyor");
  if (fireIdx !== -1 && handlerIdx !== -1) {
    const sentArgs = topLevelArgs(parenContent(cSrc, fireIdx) || "");
    const paramsSrc = parenContent(sSrc, sSrc.indexOf("function", handlerIdx));
    const params = (paramsSrc || "").split(",").map((s) => s.trim()).filter(Boolean).length;
    if (sentArgs !== params - 1) {
      g.error("Kick argüman sayısı uyuşmuyor: istemci " + sentArgs + " gönderiyor, sunucu (player hariç) " + (params - 1) + " bekliyor");
    } else {
      g.note("Kick: istemci " + sentArgs + " argüman → sunucu (player, " + (paramsSrc || "").trim() + ")");
    }
  }

  // MatchState: sunucunun gönderdiği alanlar ⊇ istemcinin okuduğu alanlar
  const sendIdx = sSrc.indexOf("stateRemote:FireAllClients");
  const payloadSrc = sendIdx === -1 ? "" : parenContent(sSrc, sendIdx) || "";
  const sentKeys = new Set([...payloadSrc.matchAll(/([A-Za-z0-9_]+)\s*=/g)].map((m) => m[1]));
  const readKeys = new Set([...cSrc.matchAll(/payload\s*\.\s*([A-Za-z0-9_]+)/g)].map((m) => m[1]));
  if (sentKeys.size === 0) g.error("sunucu MatchState payload'ı göndermiyor");
  for (const key of readKeys) {
    if (!sentKeys.has(key)) g.error("istemci payload." + key + " okuyor ama sunucu bu alanı göndermiyor");
  }
  g.note("MatchState: sunucu {" + [...sentKeys].join(",") + "} → istemci {" + [...readKeys].join(",") + "}");

  // ResetBall
  if (!cSrc.includes("resetRemote:FireServer")) g.error("istemci resetRemote:FireServer çağırmıyor (R tuşu çalışmaz)");
  if (!sSrc.includes("resetRemote.OnServerEvent:Connect")) g.error("sunucu resetRemote dinlemiyor");

  // InputEnded -> fireKick bağlantısı (şutun gerçekten tetiklenmesi)
  if (!/InputEnded\s*:\s*Connect/.test(cSrc)) g.error("istemcide UserInputService.InputEnded yok → tuş bırakılınca şut atılmaz");
  const fireKickDefined = /function\s+fireKick\s*\(/.test(cSrc);
  const fireKickCalled = [...cSrc.matchAll(/fireKick\s*\(\s*\)/g)].length;
  if (fireKickDefined && fireKickCalled <= 1) {
    g.error("fireKick() tanımlı ama çağrılmıyor (ölü kod: oyuncu şut çekemez)");
  }
});

/* ================================================================ 9) TESTLER */

let specStats = null;
gate("testler", "Testler: motor + kurulum + sunucu + istemci (spec.luau)", (g) => {
  const r = runNodeScript([path.join(ROOT, "tools", "runner.js")]);
  const out = r.stdout + "\n" + r.stderr;
  if (!out.trim()) {
    g.error("test koşucusu hiç çıktı üretmedi (VM çalışmadı?) — npm install gerekebilir");
    return;
  }
  const m = out.match(/GECEN:\s*(\d+)\s+BASARISIZ:\s*(\d+)/);
  if (!m) {
    g.error("test özeti bulunamadı; koşucu çökmüş olabilir:\n" + out.slice(-800));
    return;
  }
  specStats = { passed: parseInt(m[1], 10), failed: parseInt(m[2], 10) };
  for (const line of out.split("\n")) {
    if (/\[FAIL\]/.test(line)) g.error(line.trim());
  }
  if (specStats.failed > 0) g.error(specStats.failed + " test başarısız");
  if (specStats.passed < MIN_TESTS) {
    g.error("test sayısı geriledi: " + specStats.passed + " < " + MIN_TESTS + " (bir grup hiç çalışmıyor olabilir)");
  }
  // Grup listesi spec.luau'dan türetilir: yeni grup eklenince burası kendiliğinden güncellenir
  const specSrc = fs.readFileSync(path.join(ROOT, "tools", "spec.luau"), "utf8");
  const groups = [...specSrc.matchAll(/print\("\\n== (\d+)\./g)].map((m) => m[1]);
  if (groups.length === 0) g.error("spec.luau'da hiç test grubu başlığı bulunamadı");
  for (const n of groups) {
    if (!out.includes("== " + n + ".")) g.error("test grubu hiç çalışmadı: == " + n + ".");
  }
  g.note(groups.length + " test grubu baştan sona koştu");
  if (/KURULUM DOSYASI/.test(out)) g.error("kurulum dosyası senkron değil (koşucu uyardı)");
  g.note(specStats.passed + " kontrol geçti, " + specStats.failed + " başarısız");
});

/* ============================================================ 10) FİZİK İZİ */

gate("iz", "Fizik izi: trace.json üretimi + şema + fizik sağlamlığı", (g) => {
  const r = runNodeScript([path.join(ROOT, "tools", "runner.js"), "--trace"]);
  if (!r.ok && r.status !== 0) g.error("npm run trace başarısız: " + (r.stderr || r.stdout).slice(-400));
  const file = path.join(PREVIEW, "trace.json");
  if (!fs.existsSync(file)) {
    g.error("preview/trace.json üretilmedi");
    return;
  }
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    g.error("trace.json geçersiz JSON: " + e.message);
    return;
  }
  for (const key of ["pitch", "ball", "simHz", "shots"]) {
    if (data[key] === undefined) g.error("trace.json içinde '" + key + "' yok");
  }
  if (data.simHz !== 240) g.warn("simHz 240 değil: " + data.simHz);
  const shots = Array.isArray(data.shots) ? data.shots : [];
  if (shots.length < 5) g.error("beklenenden az senaryo: " + shots.length);

  const shotKeys = ["id", "label", "path", "maxHeight", "curve", "speedStart", "speedEnd", "goal", "bounces", "postHits", "maxSag"];
  for (const s of shots) {
    for (const k of shotKeys) if (s[k] === undefined) g.error("şut '" + s.id + "' içinde '" + k + "' yok");
    if (!Array.isArray(s.path) || s.path.length < 2) g.error("şut '" + s.id + "' yolu boş");
    for (const pt of s.path || []) {
      if (!Array.isArray(pt) || pt.length !== 3) {
        g.error("şut '" + s.id + "' yol noktası [x,y,z] değil");
        break;
      }
      for (const v of pt) {
        if (typeof v !== "number" || !isFinite(v)) {
          g.error("şut '" + s.id + "' yolunda sonlu olmayan değer: " + JSON.stringify(pt));
          break;
        }
      }
    }
  }

  const byId = Object.fromEntries(shots.map((s) => [s.id, s]));
  if (byId.falso && !(byId.falso.curve > 2)) g.error("falso senaryosunda bükülme 2 m'den az: " + byId.falso.curve);
  if (byId.duz && !(byId.duz.goal)) g.error("düz şut gol olmadı");
  if (byId.duz && !(byId.duz.speedEnd < byId.duz.speedStart)) g.error("düz şutta hava direnci hızı düşürmedi");
  if (byId.direk && !(byId.direk.postHits >= 1)) g.error("direk senaryosunda çarpışma sayılmadı");
  if (byId.direk && byId.direk.goal) g.error("direkten dönen top gol sayıldı");
  if (byId.file && !(byId.file.maxSag > 0.1)) g.error("file senaryosunda ağ esnemedi: " + byId.file.maxSag);
  if (byId.file && !(byId.file.speedEnd < 1)) g.error("ağ topu yutmadı: çıkış hızı " + byId.file.speedEnd);
  g.note(shots.length + " senaryo, " + shots.reduce((a, s) => a + (s.path ? s.path.length : 0), 0) + " yol noktası");

  // preview/index.html'in kullandığı alanlar JSON'da var mı?
  const html = fs.readFileSync(path.join(PREVIEW, "index.html"), "utf8");
  const used = new Set([...html.matchAll(/\bshot\.([\p{L}\p{N}_]+)/gu)].map((m) => m[1]));
  const have = new Set(shots.length ? Object.keys(shots[0]) : []);
  for (const field of used) {
    if (!have.has(field)) g.error("preview/index.html 'shot." + field + "' okuyor ama trace.json'da yok");
  }
  for (const field of ["pitch", "shots", "ball", "simHz"]) {
    if (html.includes("data." + field) && data[field] === undefined) {
      g.error("preview/index.html 'data." + field + "' okuyor ama trace.json'da yok");
    }
  }
  g.note("index.html ↔ trace.json alan eşleşmesi tamam (" + used.size + " alan)");
});

/* ============================================================== 11) ANİM İZİ */

gate("anim", "Animasyon izi: anim.json üretimi + şema + FK verisi", (g) => {
  const r = runNodeScript([path.join(ROOT, "tools", "runner.js"), "--anim"]);
  if (r.status !== 0) g.error("npm run anim başarısız: " + (r.stderr || r.stdout).slice(-400));
  const file = path.join(PREVIEW, "anim.json");
  if (!fs.existsSync(file)) {
    g.error("preview/anim.json üretilmedi");
    return;
  }
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    g.error("anim.json geçersiz JSON: " + e.message);
    return;
  }
  for (const key of ["fps", "joints", "bones", "scenes"]) {
    if (data[key] === undefined) g.error("anim.json içinde '" + key + "' yok");
  }
  const scenes = Array.isArray(data.scenes) ? data.scenes : [];
  if (scenes.length < 10) g.error("animasyon senaryosu 10'dan az: " + scenes.length);
  const kinds = new Set();
  let totalFrames = 0;
  for (const sc of scenes) {
    for (const k of ["label", "view", "duration", "fps", "frames"]) {
      if (sc[k] === undefined) g.error("sahne '" + sc.label + "' içinde '" + k + "' yok");
    }
    if (!Array.isArray(sc.frames) || sc.frames.length === 0) g.error("sahne '" + sc.label + "' karesiz");
    totalFrames += (sc.frames || []).length;
    if (sc.kind) kinds.add(sc.kind);
    if (sc.contact !== undefined && sc.contact > (sc.duration || 0)) {
      g.error("sahne '" + sc.label + "' temas anı süreyi aşıyor");
    }
    for (const frame of sc.frames || []) {
      if (!Array.isArray(frame) || frame.length !== (data.joints || []).length) {
        g.error("sahne '" + sc.label + "' karesi eklem sayısıyla uyuşmuyor");
        break;
      }
      for (const joint of frame) {
        if (!Array.isArray(joint) || joint.length !== 3 || joint.some((v) => typeof v !== "number" || !isFinite(v))) {
          g.error("sahne '" + sc.label + "' karesinde geçersiz eklem: " + JSON.stringify(joint));
          break;
        }
      }
    }
  }
  for (const need of ["dive", "jump", "block", "jumpDive"]) {
    if (!kinds.has(need)) g.error("kaleci hareketi eksik: " + need);
  }
  g.note(scenes.length + " sahne, " + totalFrames + " kare, kaleci türleri: " + [...kinds].join("/"));

  const html = fs.readFileSync(path.join(PREVIEW, "anim.html"), "utf8");
  const usedScene = new Set([...html.matchAll(/\b(?:scene|sc)\.([\p{L}\p{N}_]+)/gu)].map((m) => m[1]));
  const have = new Set(scenes.length ? Object.keys(scenes[0]) : []);
  for (const field of usedScene) {
    if (!have.has(field)) g.error("preview/anim.html 'scene." + field + "' okuyor ama anim.json'da yok");
  }
  for (const field of ["joints", "bones", "scenes", "fps"]) {
    if ((html.includes("json." + field) || html.includes("data." + field)) && data[field] === undefined) {
      g.error("preview/anim.html '" + field + "' bekliyor ama anim.json'da yok");
    }
  }
  g.note("anim.html ↔ anim.json alan eşleşmesi tamam (" + usedScene.size + " alan)");
});

/* ============================================================= 12) ÖNİZLEME */

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on("error", reject);
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

function httpGet(port, urlPath) {
  return new Promise((resolve) => {
    const req = http.get({ host: "127.0.0.1", port, path: urlPath, timeout: 5000 }, (res) => {
      let body = "";
      res.on("data", (d) => (body += d));
      res.on("end", () => resolve({ status: res.statusCode, type: res.headers["content-type"] || "", body }));
    });
    req.on("error", (e) => resolve({ status: 0, type: "", body: "", error: e.message }));
    req.on("timeout", () => {
      req.destroy();
      resolve({ status: 0, type: "", body: "", error: "zaman aşımı" });
    });
  });
}

async function previewGate() {
  const bag = { errors: [], warnings: [], info: [] };
  const api = { error: (m) => bag.errors.push(m), warn: (m) => bag.warnings.push(m), note: (m) => bag.info.push(m) };
  gateIndex++;
  if (!enabled("onizleme")) {
    results.push({ id: "onizleme", title: "Önizleme sunucusu: HTTP duman testi", ok: true, skipped: true, errors: [], warnings: [], info: [] });
    return;
  }
  let crashed = null;
  try {
    const port = await freePort();
    const child = spawn(process.execPath, [path.join(ROOT, "tools", "serve.js")], {
      cwd: ROOT,
      env: Object.assign({}, process.env, { PORT: String(port) }),
      stdio: ["ignore", "pipe", "pipe"],
    });
    let serverOut = "";
    child.stdout.on("data", (d) => (serverOut += d));
    child.stderr.on("data", (d) => (serverOut += d));

    // Dinlemeye başlamasını bekle
    let up = false;
    for (let i = 0; i < 50; i++) {
      await new Promise((r) => setTimeout(r, 100));
      const probe = await httpGet(port, "/");
      if (probe.status !== 0) {
        up = true;
        break;
      }
    }
    if (!up) api.error("önizleme sunucusu başlamadı: " + serverOut.slice(0, 300));
    else {
      const cases = [
        { path: "/", type: "text/html", min: 2000 },
        { path: "/index.html", type: "text/html", min: 2000 },
        { path: "/anim.html", type: "text/html", min: 2000 },
        { path: "/trace.json", type: "application/json", min: 200 },
        { path: "/anim.json", type: "application/json", min: 200 },
      ];
      for (const c of cases) {
        const r = await httpGet(port, c.path);
        if (r.status !== 200) api.error("GET " + c.path + " → " + r.status + " " + (r.error || ""));
        else if (!r.type.startsWith(c.type)) api.error("GET " + c.path + " → content-type " + r.type);
        else if (r.body.length < c.min) api.error("GET " + c.path + " → içerik çok küçük (" + r.body.length + " bayt)");
        else api.note(c.path + " → 200 " + c.type + " (" + (r.body.length / 1024).toFixed(1) + " KB)");
      }
      const missing = await httpGet(port, "/yok.html");
      if (missing.status !== 404) api.error("olmayan dosya 404 döndürmedi: " + missing.status);
      const traversal = await httpGet(port, "/../package.json");
      if (traversal.status === 200) api.error("dizin dışına erişim engellenmedi (../package.json 200 döndü)");
      else api.note("dizin dışı erişim engellendi (" + traversal.status + ")");
    }
    child.kill("SIGTERM");
  } catch (e) {
    crashed = String(e && e.stack ? e.stack.split("\n")[0] : e);
  }
  results.push({ id: "onizleme", title: "Önizleme sunucusu: HTTP duman testi", ok: crashed === null && bag.errors.length === 0, crashed, ...bag });
}

/* ================================================================= 13) BELGE */

function readmeGate() {
  gate("belge", "Belge: README sayıları/komutları gerçekle uyumlu", (g) => {
    const readmePath = path.join(ROOT, "README.md");
    if (!fs.existsSync(readmePath)) {
      g.error("README.md yok");
      return;
    }
    const readme = fs.readFileSync(readmePath, "utf8");
    // Test sayısı: canlı koşudan geliyorsa onu, kapı atlandıysa spec.luau'daki
    // `test(` bildirimlerinin statik sayımını kullan — böylece README denetimi
    // hiçbir zaman sessizce atlanmaz.
    let testCount = specStats ? specStats.passed : null;
    let countSource = "canlı koşu";
    if (testCount === null) {
      const specPath = path.join(ROOT, "tools", "spec.luau");
      if (!fs.existsSync(specPath)) {
        g.error("tools/spec.luau yok → test sayısı doğrulanamıyor");
      } else {
        const specSrc = fs.readFileSync(specPath, "utf8");
        testCount = [...specSrc.matchAll(/^\s*test\s*\(/gm)].length;
        countSource = "statik sayım (testler kapısı atlandı)";
        if (testCount === 0) g.error("spec.luau'da hiç test() bildirimi yok");
      }
    }
    if (testCount) {
      const stale = [];
      for (const m of readme.matchAll(/(\d+)\s*\/\s*(\d+)/g)) {
        // "Adım 4/6", "v2/3" gibi yol haritası ifadeleri test sonucu değildir
        const head = readme.slice(Math.max(0, m.index - 24), m.index);
        if (/Adım|adım|sürüm|versiyon|\bv\d/i.test(head)) continue;
        if (m[1] !== m[2]) stale.push(m[0] + " (geçen/toplam eşit değil)");
        if (parseInt(m[2], 10) !== testCount) stale.push(m[0] + " → gerçek " + testCount + "/" + testCount);
      }
      for (const m of readme.matchAll(/(\d+)\s+kontrol/g)) {
        if (parseInt(m[1], 10) !== testCount) stale.push(m[0] + " (gerçek " + testCount + " kontrol)");
      }
      if (stale.length) g.error("README test sayısı bayat: " + [...new Set(stale)].join(", "));
      else g.note("README test sayısı güncel (" + testCount + " · " + countSource + ")");
    }

    // Modül sayısı
    const modCount = modules.filter((m) => m.className === "ModuleScript").length;
    for (const m of readme.matchAll(/(\d+)\s+ModuleScript/g)) {
      if (parseInt(m[1], 10) !== modCount) {
        g.error("README ModuleScript sayısı bayat: " + m[0] + " (gerçek " + modCount + ")");
      }
    }
    g.note(modCount + " ModuleScript, " + modules.length + " toplam modül");

    // Animasyon senaryo sayısı
    const animPath = path.join(PREVIEW, "anim.json");
    if (fs.existsSync(animPath)) {
      try {
        const scenes = JSON.parse(fs.readFileSync(animPath, "utf8")).scenes || [];
        for (const m of readme.matchAll(/(\d+)\s+(?:senaryo|sahne)/g)) {
          const lineStart = readme.lastIndexOf("\n", m.index) + 1;
          const line = readme.slice(lineStart, readme.indexOf("\n", m.index) === -1 ? readme.length : readme.indexOf("\n", m.index));
          if (!/anim/i.test(line)) continue; // "6 senaryo" (fizik izi) gibi başka bağlamlar
          const value = parseInt(m[1], 10);
          if (value !== scenes.length && value > 5) {
            g.error("README animasyon sahne sayısı bayat: " + m[0] + " (gerçek " + scenes.length + ")");
          }
        }
      } catch (e) {
        g.warn("anim.json okunamadı: " + e.message);
      }
    }

    // README'deki komutlar gerçekten var mı?
    const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8"));
    const known = new Set(["rojo", "npm"]);
    for (const m of readme.matchAll(/(?:^|\s)(npm run [\w:-]+|npm test|npm install|rojo \w+)/gm)) {
      const cmd = m[1].trim();
      if (cmd.startsWith("npm run ")) {
        const script = cmd.slice("npm run ".length);
        if (!pkg.scripts[script]) g.error("README'deki komut package.json'da yok: " + cmd);
      } else if (cmd.startsWith("rojo ") && !known.has("rojo")) {
        g.error("bilinmeyen komut: " + cmd);
      }
    }
    g.note("README komutları package.json ile uyumlu");

    // Belgelenen tuşlar istemcide var mı?
    const client = modules.find((m) => m.key === "client/BallView");
    if (client) {
      const keys = { SPACE: "KeyCode.Space", R: "KeyCode.R", T: "KeyCode.T", F: "KeyCode.F", V: "KeyCode.V" };
      for (const [doc, code] of Object.entries(keys)) {
        const inReadme = new RegExp("\\b" + doc + "\\b").test(readme);
        const inCode = client.source.includes("Enum." + code);
        if (inCode && !inReadme) g.warn("istemci " + doc + " tuşunu kullanıyor ama README'de belgelenmemiş");
        if (!inCode && inReadme) g.error("README " + doc + " tuşunu belgeliyor ama istemcide yok");
      }
      g.note("tuş belgeleri (SPACE/R/T/F/V) kod ile uyumlu");
    }

    // verify komutu belgelenmiş mi?
    if (!readme.includes("npm run verify")) g.warn("README'de 'npm run verify' anlatılmıyor");
  });
}

/* ==================================================================== ÇIKTI */

(async function main() {
  await previewGate();
  readmeGate();

  const width = 46;
  const line = "─".repeat(72);
  console.log("");
  console.log("FootballSim — ROBLOX ENTEGRASYONU TAM DOĞRULAMA");
  console.log(line);
  let failures = 0;
  results.forEach((r, i) => {
    const label = String(i + 1).padStart(2, " ") + ". " + r.title;
    const pad = label.length < width ? " ".repeat(width - label.length) : " ";
    const mark = r.skipped ? "– ATLANDI" : r.ok ? "✓ GEÇTİ" : "✗ KALDI";
    console.log(label + pad + mark);
    for (const n of r.info) console.log("      · " + n);
    for (const w of r.warnings) console.log("      ! " + w);
    for (const e of r.errors) console.log("      ✗ " + e);
    if (r.crashed) console.log("      ✗ kapı çöktü: " + r.crashed);
    if (!r.ok) failures++;
  });
  console.log(line);
  const warnCount = results.reduce((a, r) => a + r.warnings.length, 0);
  const skipped = results.filter((r) => r.skipped).length;
  const ranCount = results.length - skipped;
  const scopeNote = skipped ? " · " + ranCount + "/" + results.length + " kapı koştu (" + skipped + " atlandı: VERIFY_ONLY)" : "";
  const testLine = specStats ? specStats.passed + " test geçti / " + specStats.failed + " başarısız · " : "";
  if (failures === 0) {
    console.log("SONUÇ: ✓ " + ranCount + "/" + ranCount + " kapı geçti" + scopeNote + " · " + testLine + warnCount + " uyarı");
    if (skipped === 0) {
      console.log("Roblox entegrasyonu TAMAMEN doğrulandı: kurulum dosyası, rojo projesi,");
      console.log("sunucu, istemci, remote sözleşmesi, API yüzeyi, fizik/animasyon izleri,");
      console.log("önizleme sunucusu ve belge tutarlılığı.");
    } else {
      console.log("DİKKAT: " + skipped + " kapı VERIFY_ONLY nedeniyle ATLANDI — bu, tam");
      console.log("doğrulama değildir. Tam kanıt için: npm run verify");
    }
    console.log(line);
    process.exit(0);
  } else {
    console.log("SONUÇ: ✗ " + failures + " kapı KALDI" + scopeNote + " · " + testLine + warnCount + " uyarı");
    console.log(line);
    process.exit(1);
  }
})();
