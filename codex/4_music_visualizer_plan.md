# 音乐可视化与 3D 播放器计划

## 目标

参考 Mineradio 一类沉浸式音乐播放器体验，在当前 Godot 音乐应用中逐步实现：

1. [已完成 MVP] 随音乐节奏律动的粒子系统。
2. [已完成 MVP] 鼓点驱动的泛光、镜头、声波扩散效果。
3. [已完成 MVP] 体素/柱阵城市随频谱起伏的科幻场景。
4. [已完成 MVP] 3D 歌单架，用立体卡片管理歌单与当前播放内容。
5. [已完成 MVP] 普通播放器 UI 与沉浸式 3D 视觉模式共存，并可在设置中关闭。
6. [新目标] 对标 Mineradio 的封面粒子舞台：封面点阵粒子、双层 Bloom、频谱 Shader、鼓点 Ripple、光流背景。

## 当前状态

### Mineradio 类似体验进度总览

当前整体状态：已完成可运行 MVP，约达到 Mineradio 技术结构的 75% 左右。核心封面粒子舞台、双层 Bloom、频谱驱动、鼓点 ripple、光流背景、3D 播放舞台层、玻璃态播放器前景、远程封面、主色调联动和性能开关已经接入；主要差距不再是“有没有功能”，而是“实机观感是否足够精致、动效是否足够像、性能策略是否足够稳”。

#### 已接近 Mineradio 的部分

1. 封面点阵粒子主视觉：已完成 MVP。
   - 已使用封面纹理采样生成点阵粒子。
   - 已支持默认封面、真实封面、本地封面和远程封面。
   - 已支持 Low/Medium/High 粒子密度。
   - 已支持封面切换 burst 和上一张/当前封面混合。

2. 双层粒子与 Bloom：已完成 MVP。
   - 已有主粒子层 `CoverParticleMesh`。
   - 已有 additive Bloom 副层 `CoverBloomMesh`。
   - 已支持设置页 Bloom 强度调节。

3. 音频频谱驱动：已完成 MVP。
   - 已输出 kick、bass、vocal、instrument_mid、treble、treble_air、rms、energy_onset。
   - Shader 已使用细频段驱动低频冲击、人声浮雕、高频闪点和起音爆发。

4. 鼓点 ripple 与视觉反馈：已完成 MVP。
   - 鼓点可触发 ripple、Bloom 闪光、声波环和相机轻微运动。
   - 切歌、收藏也已有短视觉反馈。

5. 光流背景、扫描线、噪声、暗角：已完成 MVP。
   - 已有 `mineradio_light_flow_overlay.gdshader`。
   - 支持 RGB 错位、动态线场、fiber 光丝、grain、vignette 和 onset 脉冲。

6. 前景播放器融合：已完成 MVP。
   - 全屏播放器已改为透明黑玻璃，让 3D 粒子舞台透出。
   - 迷你播放器已同步深色玻璃态和青金配色。

7. 设置与性能控制：已完成 MVP。
   - 已支持 Off/Low/Medium/High。
   - 已支持 Mineradio / City 模式切换。
   - 已支持粒子强度和 Bloom 强度调整，并显示当前百分比。
   - 移动端默认 Low。

8. 3D 播放舞台层次：已完成第一轮增强。
   - 已在封面粒子背后预铺 `MineradioStageFrame`。
   - 已新增外环、中环、内层玻璃三层 3D 舞台面。
   - 舞台层会跟随主色、低频、鼓点、切歌和收藏反馈变化。
   - 解决原先“点阵贴片 + 背景光流”过于平面的第一层问题。

#### 仍未达到 Mineradio 观感的部分

1. 实机视觉精修：未完成。
   - 需要在真实窗口里继续调中心构图、点大小、透明度、Z 轴起伏、Bloom 和背景光流权重。
   - 3D 舞台层已经补上，但仍需要实机调大小、距离、亮度和前景遮挡关系。

2. 粒子运动细腻度：部分完成。
   - 已有多频段驱动和多预设形变。
   - 还缺少更接近 Mineradio 的微粒散开、回弹、呼吸、边缘游离感。

3. 鼓点节奏精度：部分完成。
   - 已有实时 kick/onset 检测。
   - 未做 Mineradio 的离线 beatmap、长音频 DJ 模式、pulseBeats/cameraBeats 分层。

4. Shader 数据纹理体系：部分完成。
   - 已有 edge/depth 支持纹理。
   - 未做完整 ripple 数据纹理、多 ripple 场、上一张封面更复杂的时序过渡。

5. 可视化失败回退：未完成。
   - 视觉场景加载失败、Shader 失败、封面下载异常时，还需要更明确地回退普通背景。

6. City 模式精修：部分完成。
   - 已有 MultiMesh 城市、道路光带和雾层。
   - 还需要实机调参、镜头构图、雾效深度和道路层次增强。

7. 3D 歌单架最终 polish：部分完成。
   - 已有 3D 卡片、点击、封面贴图、当前播放高亮和第一轮舞台层次增强。
   - 已完成第一轮 Mineradio 横向黑玻璃卡片和被挤压布局修复。
   - 还缺少 Tween 版动效、卡片点击进入详情的最终交互打磨和实机视觉细调。

#### 下一步优先级

1. 第一优先级：实机视觉精修。
   - 调 `CoverParticleStage3D` 位置、尺寸和相机距离。
   - 调 `cover_particle_stage.gdshader` 的点大小、透明度、Z 轴起伏。
   - 调 `cover_particle_bloom.gdshader` 的 Bloom 强度和点尺寸。
   - 调光流背景权重，避免抢封面粒子主视觉。

2. 第二优先级：补可视化失败回退。
   - Visualizer 场景不可用时自动隐藏 3D 层。
   - Shader/封面加载失败时保留普通深色背景。
   - 关闭视觉效果后确保不继续更新或下载。

3. 第三优先级：增强 Mineradio 细节。
   - 加强粒子边缘游离感和封面轮廓呼吸。
   - 细分鼓点事件强度，区分 ripple、camera、burst。
   - 评估是否需要离线 beatmap。

4. 第四优先级：City 模式和 3D 歌单架 polish。
   - City 模式做实机亮度、雾、道路层次调参。
   - 3D 歌单架继续补 Tween 动效、卡片进入详情和真实窗口细节调参。

### 已完成

1. 已新增 `default_bus_layout.tres`，在 Master Bus 上配置 `AudioEffectSpectrumAnalyzer`。
2. 已新增 `MusicAppSpectrumController`：
   - `res://scripts/ui/music_app/controllers/global/music_app_spectrum_controller.gd`
   - 输出 bass/mid/treble/volume。
   - 支持 `spectrum_changed` 和 `beat_detected` 信号。
3. 已新增音乐可视化场景：
   - `res://scenes/ui/music_app/visualizer/music_app_visualizer.tscn`
   - 场景内已铺设 SubViewport、Camera3D、WorldEnvironment、GPUParticles3D、49 个体素城市柱体、4 个声波环。
4. 已新增音乐可视化驱动：
   - `res://scripts/ui/music_app/views/visualizer/music_app_visualizer_view.gd`
   - 只驱动场景内已有节点属性，不在运行时创建视觉节点。
5. 已将 `MusicAppVisualizer` 实例化到主场景：
   - `res://scenes/music_app_showcase_scene.tscn`
6. 已新增 3D 歌单架场景：
   - `res://scenes/ui/music_app/playlist/playlist_shelf_3d.tscn`
   - 场景内已铺设 5 张 3D 歌单卡片、SubViewport、Camera3D、灯光、左右切换按钮、播放按钮。
7. 已新增 3D 歌单架驱动：
   - `res://scripts/ui/music_app/views/playlist/music_app_playlist_shelf_3d.gd`
   - 复用预置卡片填充歌单信息，不在运行时创建卡片节点。
8. 已将 3D 歌单架接入歌单详情页：
   - `res://scenes/ui/music_app/playlist/music_app_playlist_page.tscn`
9. 已新增歌单选择接口：
   - `MusicAppPlaylistController.select_playlist(index)`
10. 已新增视觉设置数据：
   - `MusicAppStateData.visualizer_settings`
   - 字段包含 `enabled`、`quality`、`particles`、`bloom`。
11. 已在设置页接入视觉效果控件：
   - 启用沉浸式视觉开关。
   - Off/Low/Medium/High 性能档位。
   - 粒子强度滑条。
   - 泛光强度滑条。
12. 已让视觉设置即时应用：
   - `MusicAppVisualizer` 根据设置切换显示、处理状态、粒子数量、泛光强度。
   - `PlaylistShelf3D` 根据设置切换显示和处理状态。
13. 已通过校验：
   - `Godot --headless --path . --check-only --quit`
   - `Godot --headless --path . --quit-after 3`
   - 设置页场景独立加载。
   - Godot MCP 启动主场景后 `errors: []`

14. 已新增移动端默认视觉策略：
   - Android/iOS/Web 默认 Low 档。
   - 移动端默认降低粒子强度和泛光强度。
15. 已新增播放状态联动 MVP：
   - 播放时进入 active 状态。
   - 暂停/未播放时进入 idle 状态。
   - 切歌时触发一次视觉脉冲和声波环。
16. 已新增 MultiMesh 体素城市：
   - 场景内已预铺 `MultiMeshCity` 节点。
   - `music_app_voxel_city.gd` 负责配置和更新 `MultiMesh` 数据。
   - Low 使用 16x16，Medium 使用 24x24，High 使用 32x32。
   - 现有 49 个 `Pillar_*` 节点保留为 fallback。
17. 已增强 3D 歌单架交互：
   - 场景内已预铺 5 个透明点击热区。
   - 点击左右卡片可直接切换歌单。
   - 点击中心卡片可播放当前歌单。
   - 当前播放歌单有独立高亮颜色和发光强度。
18. 已新增 Mineradio 风格视觉 polish：
   - `music_app_visualizer.tscn` 场景内预铺 `MineradioBackdrop`。
   - 新增 `StarDustParticles` 星尘粒子层。
   - 新增 4 条半透明青绿色/金色斜向光带。
   - 新增 `VisualizerScanlineOverlay` 扫描线、暗角和轻微噪声叠层。
   - `music_app_visualizer_view.gd` 只驱动已有节点的粒子数量、速度、透明度、发光和位移，不在运行时创建视觉节点。
19. 已完成 Mineradio GitHub 源码调研：
   - 仓库：`https://github.com/XxHuberrr/Mineradio`
   - 当前调研 commit：`6b130103f759e5dcd1e133700071c8216b8fa5a6`
   - 技术栈：Electron + Three.js + WebAudio + GSAP + music-tempo。
   - 主粒子不是普通随机粒子，而是封面纹理采样后的 `grid x grid` 点阵。
   - Three.js 使用 `BufferGeometry`，每个粒子带 `position`、`aUv`、`aRand`。
   - Shader uniform 包含 `uBass`、`uMid`、`uTreble`、`uBeat`、`uEnergy`、`uBurstAmt`、`uCoverTex`、`uPrevCoverTex`、`uEdgeTex`、`uRippleTex`。
   - 主视觉包含正常粒子层 `particles` 和加法混合溢光层 `bloomParticles`。
   - 音频分析使用 WebAudio `AnalyserNode`，拆 kick、人声、中高频、treble、RMS，并做动态峰值和平滑。
   - 长音频/DJ 模式有离线 beatmap，输出 `beats`、`pulseBeats`、`cameraBeats`。
   - 启动页/背景光流是独立全屏 WebGL fragment shader，包含 RGB 通道错位、斜向光流、scanline、grain、vignette。
20. 已完成封面粒子舞台 MVP：
   - 新增 `res://scripts/ui/music_app/views/visualizer/music_app_cover_particle_stage.gd`。
   - 新增 `res://shaders/ui/music_app/visualizer/cover_particle_stage.gdshader`。
   - 新增 `res://shaders/ui/music_app/visualizer/cover_particle_bloom.gdshader`。
   - `music_app_visualizer.tscn` 场景内已预铺 `CoverParticleStage3D`、`CoverParticleMesh`、`CoverBloomMesh`。
   - 使用 `ArrayMesh` 生成封面点阵 quad 数据，节点仍预铺在场景内。
   - 支持 Low/Medium/High 点阵密度：75x75、119x119、183x183。
   - 支持默认程序化封面纹理，当前没有真实封面时也能显示主体视觉。
   - 支持本地 `res://` / `user://` artwork 纹理加载。
   - 支持主粒子层 + additive Bloom 副层。
   - 支持频谱驱动 Z 轴起伏、亮度、点尺寸。
   - 支持鼓点 ripple 和切歌 burst。
21. 已完成 Mineradio 风格第二轮调优：
   - 新增 `res://shaders/ui/music_app/visualizer/mineradio_light_flow_overlay.gdshader`。
   - `VisualizerScanlineOverlay` 已切换为光流、RGB 霓虹、扫描线、噪声、暗角叠层。
   - 默认 Mineradio 风格下隐藏 `VoxelCity`，避免体素柱阵抢主视觉。
   - 降低星尘密度、速度和透明度，改成暗场尘埃。
   - 收敛封面点阵尺寸和 Bloom 强度，避免显示成整块青色网格。
   - 无真实封面时显示圆形唱片/光盘点阵轮廓，而不是矩形封面墙。
22. 已完成前景播放器 Mineradio 风格 polish：
   - `music_app_player_page.tscn` 已新增半透明暗场氛围层、扫描线/噪声/暗角 Canvas Shader。
   - 全屏播放器背景改为透明黑玻璃，让 3D 粒子舞台能透出。
   - 封面区改为唱片式圆环、金色核心、青金双光晕和玻璃边框。
   - 播放控制区新增黑玻璃底板、金色主播放按钮、青色描边次级按钮。
   - `music_app_mini_player.tscn` 已改成底部黑玻璃胶囊，封面、进度环、列表按钮统一青金配色。
   - `music_app_mini_player_view.gd` 默认封面占位色已同步为深色唱片/金色字符。
23. 已完成可视化远程封面接入：
   - `music_app_visualizer.tscn` 场景内已预铺 `CoverArtworkRequest`。
   - `music_app_cover_particle_stage.gd` 使用预铺 HTTPRequest 下载远程 `artwork_url`。
   - 支持远程 PNG/JPG/WebP 解码。
   - 支持内存缓存和 `user://music_app/visualizer_artwork` 磁盘缓存。
   - 远程封面下载完成后会回填封面粒子舞台并触发一次 burst/ripple。
24. 已完成封面粒子 edge/depth 与多预设形变：
   - `music_app_cover_particle_stage.gd` 会从当前封面生成 edge/depth 两张支持纹理。
   - `cover_particle_stage.gdshader` 已接入 edge/depth，增强轮廓发光、透明度和 Z 轴层次。
   - `cover_particle_bloom.gdshader` 已同步 edge/depth，Bloom 层会强化封面边缘。
   - 按曲目 key 稳定选择 4 种形变预设：基础封面、旋涡、环形隧道、横向声波。
   - 远程封面下载完成后会重新生成 edge/depth 支持纹理并触发切换动画。
25. 已完成详细频谱输出 MVP：
   - `MusicAppSpectrumController` 新增 `detailed_spectrum_changed` 信号。
   - 输出 `kick`、`bass`、`vocal`、`instrument_mid`、`treble`、`treble_air`、`rms`、`energy_onset`。
   - 旧的 `spectrum_changed` 信号保留，兼容现有城市、星尘和基础粒子逻辑。
   - 鼓点检测改用更窄的 kick 频段，减少中低频铺底导致的误触发。
   - `MusicAppVisualizerView` 已将详细频谱转发给封面粒子舞台。
   - `cover_particle_stage.gdshader` 和 `cover_particle_bloom.gdshader` 已使用细频段驱动低频冲击、人声浮雕、高频闪点和起音爆发。
26. 已完成光流 Shader 增强 MVP：
   - `mineradio_light_flow_overlay.gdshader` 新增 RGB 错位、动态线场、fiber 光丝、颗粒强度和 onset 脉冲。
   - 新增可调参数：`rgb_shift`、`flow_strength`、`line_density`、`grain_alpha`、`air`、`onset`。
   - `MusicAppVisualizerView` 会根据 `treble_air`、`energy_onset`、`rms` 和性能档位动态调节光流强度。
   - Low 档会降低线场密度、RGB 错位和颗粒强度，减少移动端视觉负担。
27. 已完成 3D 歌单架封面贴图 MVP：
   - `playlist_shelf_3d.tscn` 场景内已预铺 `PlaylistArtworkRequest`。
   - `music_app_playlist_shelf_3d.gd` 会使用歌单第一首歌曲的 `artwork_url` 作为 3D 卡片封面。
   - 支持本地 `res://` / `user://` 封面。
   - 支持远程 PNG/JPG/WebP 下载，并缓存到 `user://music_app/playlist_shelf_artwork`。
   - 没有真实封面时会生成程序化唱片风格占位纹理。
   - 远程封面加载完成后会回填当前仍可见的预铺卡片，不创建新的 3D 节点。
28. 已完成视觉资源释放 MVP：
   - `MusicAppShowcaseController` 在视觉关闭或 Off 档时不再处理频谱控制器。
   - `MusicAppVisualizerView` 在关闭时停止粒子、隐藏声波环、关闭城市节点并重置视觉脉冲状态。
   - `MusicAppCoverParticleStage` 在关闭时取消远程封面请求、清空请求上下文并重置 ripple/burst。
   - `MusicAppPlaylistShelf3D` 在关闭时取消远程歌单封面请求并清空下载队列。
29. 已完成城市独立视觉模式 MVP：
   - `MusicAppStateData.visualizer_settings` 新增 `mode` 字段，默认 `mineradio`。
   - 设置页新增视觉模式按钮：`Mineradio` / `City`。
   - `MusicAppVisualizerView` 会根据 `mode` 切换封面粒子舞台和 `MultiMeshCity`。
   - `MusicAppCoverParticleStage` 在 City 模式下会停止自身并取消封面下载。
   - 默认 Mineradio 模式仍不显示体素城市，避免城市和封面粒子主视觉混在一起。
30. 已完成 City 模式场景层次 MVP：
   - `music_app_visualizer.tscn` 在 `VoxelCity` 下预铺 `CitySceneLayers`。
   - 已预铺 `CityGround` 城市地面。
   - 已预铺 4 条道路光带：南北、东西、两条对角线。
   - 已预铺 `CityFogLow` 和 `CityFogBack` 两层透明雾面。
   - `MusicAppVisualizerView` 会在 City 模式中根据 bass/mid/treble/onset/rms 驱动地面亮度、道路发光和雾层漂移。
31. 已完成收藏歌曲短粒子反馈 MVP：
   - 新增 `MusicAppFavoriteChangedEvent`。
   - `MusicAppPlayerController.toggle_like_current_track()` 在收藏状态变化后发出事件。
   - `MusicAppShowcaseController` 监听事件并转发给 `MusicAppVisualizer`。
   - `MusicAppVisualizerView` 会触发短粒子闪烁、Beat 灯增强、声波环和封面粒子 ripple。
   - `MusicAppCoverParticleStage` 会在收藏/取消收藏时触发偏移 ripple 和短 burst。
32. 已完成当前歌曲主色调联动 MVP：
   - `MusicAppCoverParticleStage` 会从真实封面采样主色。
   - 没有真实封面时按平台、来源、歌手、标题生成稳定主色。
   - 主色会写入封面粒子 Shader 和 Bloom Shader 的 `tint_color`。
   - `MusicAppVisualizerView` 会把主色同步到光流叠层、星尘粒子、斜向光带、Beat 灯和 City 模式道路/雾层。
   - 远程封面下载完成后会重新提取主色并平滑过渡。
33. 已完成设置页数值显示 MVP：
   - `music_app_settings_page.tscn` 在粒子强度和泛光强度滑条右侧预铺数值 Label。
   - `MusicAppSettingsView` 会在刷新设置页时同步当前百分比。
   - 拖动滑条时百分比会立即更新，便于后续实机调参。
34. 已完成 3D 播放区域 Mineradio 舞台层次增强：
   - 新增 `res://shaders/ui/music_app/visualizer/mineradio_stage_frame.gdshader`。
   - `music_app_visualizer.tscn` 在 `CoverParticleStage3D` 下预铺 `MineradioStageFrame`。
   - 已预铺 `StageOuterOrbit`、`StageMidOrbit`、`StageInnerGlass` 三层舞台面。
   - `MusicAppVisualizerView` 会缓存并驱动这些舞台层的主色、鼓点、低频、旋转、缩放和透明度。
   - 目的：让 3D 播放区域从平面点阵变成有空间结构的封面粒子舞台。
35. 已完成 3D 歌单架舞台层次增强 MVP：
   - `playlist_shelf_3d.tscn` 已复用 `mineradio_stage_frame.gdshader`。
   - 在 `ShelfRoot` 下预铺 `ShelfStage`。
   - 已新增 `ShelfBackHalo`、`ShelfCenterHalo`、`ShelfPlatform`、`ShelfFrontRail`、`ShelfBackRail`、`ShelfCenterPedestal`。
   - `MusicAppPlaylistShelf3D` 会缓存并驱动这些舞台节点。
   - 舞台层会根据当前中心歌单封面/占位色生成主色，并随选择切换、当前播放状态做呼吸、旋转、发光。
   - 目的：让 3D 歌单从“几张卡片排开”变成带轨道、底座和中心高亮的小型 carousel 舞台。
36. 已完成 Mineradio 歌单卡片样式对标第一轮：
   - 已查看 Mineradio `docs/3D_PLAYLIST_SHELF_MEMORY.md` 和 `public/index.html` 的 `makeShelfManager()` / `drawCard()` / `placeCard()`。
   - 结论：Mineradio 歌单架核心不是竖向封面盒，而是横向黑玻璃实体卡、左封面、右信息、底部律动线、选中描边、中心浮起和独立 accent 色。
   - `playlist_shelf_3d.tscn` 中 5 张预铺卡已从竖向封面盒改成横向玻璃卡结构。
   - 每张卡新增预铺 `CardGlass`、左侧 `Cover` 和底部 `CardAccentRail`。
   - `MusicAppPlaylistShelf3D` 会驱动玻璃底、封面 tile、accent rail、文字颜色和当前播放高亮。
   - 目的：让 Godot 3D 歌单架更接近 Mineradio 的 PSP/黑玻璃 carousel 卡片质感。
37. 已完成 3D 歌单架布局修复第一轮：
   - `PlaylistShelf3D` 高度从 190 提升到 300，避免 3D 舞台被压成横条。
   - `PlaylistShelfViewport` 同步提升到 430x300。
   - `ShelfCamera` 后移并扩大视角，减少横向卡片裁切。
   - 横向玻璃卡、封面 tile、文字和底部 accent rail 均缩小一档。
   - 中心卡片缩放从 1.18 收敛到 1.02，避免遮挡左右卡片。
   - 原有 `Play` / `<` / `>` 可见按钮已隐藏，交互改由预铺透明点击热区承接，避免控件压在 3D 卡片上。
38. 已完成独立沉浸式 3D 播放器场景 MVP：
   - 新增 `res://scenes/ui/music_app/immersive/immersive_3d_player.tscn`。
   - 新增 `res://scripts/ui/music_app/views/immersive/music_app_immersive_3d_player.gd`。
   - 场景独立预铺 `MusicAppVisualizer` 和 `PlaylistShelf3D`，不依赖普通播放器页和普通歌单页。
   - 内置 demo 歌单、demo 曲目和 demo 频谱输入，直接运行该场景即可看到 3D 背景、封面粒子、3D 歌单架和节奏反馈。
   - 支持点击 3D 歌单卡片切换/播放，支持顶部 Play/Pause 和 Mineradio/City 模式切换。
   - 键盘支持：左右方向切换歌单，确认键播放/暂停，`M` 切换 Mineradio/City。
   - 修复 `MusicAppVoxelCity` 在重复配置 MultiMesh 时 instance_count 未清零导致的错误日志。
39. 已完成独立 3D 场景截图反馈修复第一轮：
   - 修正上一版“两个 SubViewport 直接叠放”导致的两个圆形舞台重叠问题。
   - `MusicAppVisualizer` 在独立场景中收敛到上半舞台，避免覆盖 3D 歌单区域。
   - `PlaylistShelf3D` 在独立场景中扩大到下半舞台，并增加暗场隔离层，让 3D 歌单卡片更明确。
   - 在独立场景中隐藏歌单架自己的 `ShelfBackHalo` 和 `ShelfCenterHalo`，避免和封面粒子圆盘混在一起。
   - `PlaylistShelf3D` 的透明点击热区改为比例锚定，放大/缩放场景后仍能点到对应卡片。
40. 已完成独立 3D 场景 Mineradio 首屏布局修复：
   - `MusicAppVisualizer` 恢复全屏铺底，首屏重新以封面粒子主视觉为核心。
   - 顶部信息框移除，改成底部黑玻璃播放器胶囊，更接近 Mineradio 的底部控制条结构。
   - 中心新增大标题和副标题，跟随当前 demo 曲目同步。
   - 3D 歌单架默认收起，避免首屏出现上下两个廉价舞台。
   - 底部新增 `Shelf` 按钮和 `S` 快捷键，用覆盖层展开 3D 歌单架。
   - `Mode` / `Play` / `Shelf` 控件统一收进底部胶囊。

### 待做

1. 实机视觉细调：
   - 微调 `CoverParticleStage3D` 位置和尺寸。
   - 微调封面点大小、Z 轴起伏、Bloom 和背景光流权重。
2. 独立沉浸式 3D 播放器继续增强：
   - 把 demo 数据切换为真实播放状态和真实歌单数据。
   - 将 3D 歌单架从独立 SubViewport 进一步并入同一个 3D WorldRoot，形成真正统一的 3D 空间；这是解决“两个 3D 场景叠在一起不像同一个界面”的关键步骤。
   - 增加从普通入口进入该独立 3D 场景的路由。
3. 3D 歌单架继续实机细调：
   - 根据真实窗口继续调卡片间距、相机距离、文字大小和舞台亮度。
   - 补 Tween 版切换动效。
   - 补中心卡片进入详情的最终交互 polish。
4. 后续再做 City 模式实机调参和可视化加载失败回退。

### 下一步建议

优先做“实机视觉细调”。理由：

1. 封面点阵、Bloom、频谱起伏、鼓点 ripple、真实封面、edge/depth、多预设、详细频谱和光流增强已经完成。
2. 下一步差距主要是窗口观感调参：点大小、Z 轴起伏、Bloom、背景光流权重和前景遮罩。
3. 需要在真实窗口里根据效果继续压过曝、调中心构图和前景可读性。

推荐下一步拆成 5 个小任务：

1. 把 `PlaylistShelf3D` 的 3D 节点拆成可复用的 `Node3D` 子舞台。
2. 将歌单卡片、轨道、底座和点击投射接入 `MusicAppVisualizer` 的 `WorldRoot`。
3. 用一台相机统一管理封面粒子舞台和歌单舞台，避免两个 viewport 视觉割裂。
4. 再接真实播放状态和真实歌单数据。
5. 最后根据实机观感继续压过曝、调中心构图和前景可读性。

### 最近验证

最近一次实现后已验证：

1. `Godot --headless --path . --check-only --quit` 通过。
2. `Godot --headless --path . --quit-after 3` 通过。
3. `MusicAppStateData.visualizer_settings` 标准化通过：
   - 非法档位会回退到 `medium`。
   - 粒子强度会限制在 `0.25..1.5`。
   - 泛光强度会限制在 `0.0..1.5`。
4. 可视化场景独立启动通过。
5. `MultiMeshCity` 默认 Medium 档实例数为 576。
6. Godot MCP 启动主场景后 `errors: []`。
7. Mineradio 风格视觉 polish 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
8. 封面粒子舞台 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
9. Mineradio 风格第二轮调优后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
10. 前景播放器玻璃态 polish 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
11. 可视化远程封面接入后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
12. 封面粒子 edge/depth 与多预设形变后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
13. 详细频谱输出 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
14. 光流 Shader 增强 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
15. 3D 歌单架封面贴图 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
16. 视觉资源释放 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
17. 城市独立视觉模式 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
18. City 模式场景层次 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
19. 收藏歌曲短粒子反馈 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
20. 当前歌曲主色调联动 MVP 后，Godot headless 和 MCP 主场景启动均通过，`errors: []`。
21. 设置页数值显示 MVP 后，Godot headless 和设置页场景独立加载均通过。
22. 3D 播放区域 Mineradio 舞台层次增强后，Godot headless 和可视化场景独立加载均通过。
23. 3D 歌单架舞台层次增强后，Godot headless、歌单架场景独立加载和 MCP 主场景启动均通过，`errors: []`。
24. Mineradio 歌单卡片样式对标第一轮后，Godot headless、歌单架场景独立加载和 MCP 主场景启动均通过，`errors: []`。
25. 3D 歌单架布局修复第一轮后，以下验证通过：
   - `Godot --headless --path . --check-only --quit`
   - `Godot --headless --path . scenes/ui/music_app/playlist/playlist_shelf_3d.tscn --quit-after 2`
   - `Godot --headless --path . scenes/ui/music_app/playlist/music_app_playlist_page.tscn --quit-after 2`
   - Godot MCP 启动主场景后 `errors: []`
26. 独立沉浸式 3D 播放器场景 MVP 后，以下验证通过：
   - `Godot --headless --path . scenes/ui/music_app/immersive/immersive_3d_player.tscn --quit-after 3`
   - `Godot --headless --path . --check-only --quit`
   - `Godot --headless --path . --quit-after 3`
27. 独立 3D 场景截图反馈修复第一轮后，以下验证通过：
   - `Godot --headless --path . scenes/ui/music_app/immersive/immersive_3d_player.tscn --quit-after 3`
   - `Godot --headless --path . --check-only --quit`
   - `Godot --headless --path . scenes/ui/music_app/playlist/music_app_playlist_page.tscn --quit-after 2`
   - Godot MCP 启动独立场景后 `errors: []`
28. 独立 3D 场景 Mineradio 首屏布局修复后，以下验证通过：
   - `Godot --headless --path . scenes/ui/music_app/immersive/immersive_3d_player.tscn --quit-after 3`
   - `Godot --headless --path . --check-only --quit`
   - `Godot --headless --path . scenes/ui/music_app/playlist/music_app_playlist_page.tscn --quit-after 2`
   - Godot MCP 启动独立场景后 `errors: []`

### Mineradio 技术复现计划

目标：先做接近 Mineradio 的封面粒子主舞台，再处理原创化、视觉差异化和性能细节。

#### A. 源码结论

1. Mineradio 主粒子系统使用 Three.js `BufferGeometry + ShaderMaterial + Points`。
2. 粒子数量来自封面清晰度：
   - 默认约 119x119。
   - 高档约 183x183。
3. 每个粒子有：
   - 3D 位置。
   - 封面 UV。
   - 随机种子。
4. Shader 采样：
   - 当前封面纹理。
   - 上一张封面纹理。
   - 边缘/深度纹理。
   - Ripple 数据纹理。
5. 视觉层：
   - 正常粒子层。
   - Bloom 溢光粒子层。
   - 背景光流/星尘层。
   - 扫描线、噪声、暗角。
6. 音频输入：
   - kick 低频。
   - vocal 人声段。
   - instrument mid 中高乐器。
   - treble 高频。
   - RMS 能量。
   - onset/beat pulse。
7. 鼓点系统：
   - 实时 beat 检测。
   - 离线 beatmap 补强。
   - beat 驱动相机、ripple、粒子亮度和爆发。

#### B. Godot 对标设计

1. `CoverParticleStage3D`
   - 类型：`Node3D`。
   - 场景内预铺，不运行时创建。
   - 挂载 `music_app_cover_particle_stage.gd`。

2. `CoverParticleMesh`
   - 类型：`MeshInstance3D`。
   - 使用 `ArrayMesh` 或预置 `MultiMeshInstance3D` 承载点阵。
   - 第一版优先用 `ArrayMesh` 构建点阵 quad/point-like mesh。

3. `CoverBloomMesh`
   - 类型：`MeshInstance3D`。
   - 复用同一份粒子数据。
   - Shader 点尺寸更大、透明度更低、emission 更强。

4. `CoverLightFlowOverlay`
   - 类型：`ColorRect` 或相机前 Quad。
   - 使用 Godot `canvas_item shader` 实现斜向光流、RGB 错位、scanline、grain、vignette。

5. `MusicAppSpectrumController`
   - 从现有 bass/mid/treble 扩展到更细频段。
   - 保留旧信号兼容现有城市和粒子。
   - 新增 `detailed_spectrum_changed` 信号。

6. `MusicAppVisualizerView`
   - 继续负责视觉总控。
   - 将频谱、鼓点、切歌、封面传给 `CoverParticleStage3D`。
   - 城市、星尘、光带作为背景层保留。

#### C. MVP 验收

1. 无封面时显示默认点阵渐变。
2. 有封面时点阵颜色能显示封面主轮廓。
3. 播放音乐时点阵 Z 轴、亮度、大小随频谱变化。
4. 鼓点触发一次 ripple 起伏和 Bloom 闪光。
5. 切歌时有短促 burst，并能从上一张封面渐变到新封面。
6. Low/Medium/High 档控制点阵密度和 Bloom 强度。
7. 当前城市/星尘/光带仍在背景，但不抢封面粒子主视觉。
8. Godot headless 校验和 MCP 主场景启动无错误。

#### D. 一比一复现后的处理

1. 替换 Mineradio 命名，改成当前项目自己的视觉命名。
2. 调整色彩、构图和交互，避免长期停留在直接临摹风格。
3. 优化移动端性能。
4. 再做前景玻璃态、3D 歌单架封面、城市雾效。

### 下个实现批次

目标：实机视觉细调和剩余交互反馈。

建议顺序：

1. 实机观察封面点阵主体是否够明显。
2. 调点尺寸、透明度、Bloom、Z 轴起伏幅度。
3. 微调 City 模式地面、道路光带和雾层透明度。
4. 补可视化加载失败时回退普通背景。
5. 完成后重新跑 Godot headless 校验和 MCP 启动日志。

## 设计原则

1. 先做稳定的音频分析输入，再做视觉表现。
2. 视觉效果必须可关闭，移动端默认使用较低性能档位。
3. 不做真实流体模拟，第一阶段使用 Shader、粒子、透明环、Bloom 模拟流体和声波感。
4. 大量重复物体使用 `MultiMeshInstance3D` 或 Shader 参数驱动，避免每帧创建/删除节点。
5. 保持现有播放器、弹窗、Controller/View 结构，不把 3D 逻辑塞进普通 UI View。
6. 对标 Mineradio 阶段允许先按其技术结构做一比一复现，但视觉节点仍必须预铺在场景内；后续再做命名、色彩、交互和视觉语言替换。

## 推荐目录

1. `scripts/ui/music_app/controllers/global/music_app_spectrum_controller.gd`
   - 负责读取频谱、平滑数值、检测鼓点。

2. `scripts/ui/music_app/views/visualizer/music_app_visualizer_view.gd`
   - 负责 3D 可视化视图状态和视觉节点绑定。

3. `scenes/ui/music_app/visualizer/music_app_visualizer.tscn`
   - 3D 可视化主场景，包含粒子、城市、相机、环境光。

4. `scripts/ui/music_app/views/visualizer/music_app_voxel_city.gd`
   - 已新增，负责 MultiMesh 体素城市实例更新。

5. `scripts/ui/music_app/views/visualizer/music_app_shockwave_ring.gd`
   - 负责鼓点声波环扩散。

6. `scenes/ui/music_app/playlist/playlist_shelf_3d.tscn`
   - 3D 歌单架原型场景。

7. `scripts/ui/music_app/views/visualizer/music_app_cover_particle_stage.gd`
   - 已新增，负责封面点阵粒子 Mesh 数据、Shader 参数、封面纹理、切歌渐变和 ripple slot。

8. `shaders/ui/music_app/visualizer/cover_particle_stage.gdshader`
   - 已新增，负责封面粒子位移、颜色采样、频谱起伏和 ripple。

9. `shaders/ui/music_app/visualizer/cover_particle_bloom.gdshader`
   - 已新增，负责溢光粒子层。

10. `shaders/ui/music_app/visualizer/mineradio_light_flow_overlay.gdshader`
   - 已新增，负责全屏光流、扫描线、噪声和暗角。

11. `scenes/ui/music_app/immersive/immersive_3d_player.tscn`
   - 已新增，独立沉浸式 3D 播放器入口，组合 3D 可视化主场景和 3D 歌单架。

12. `scripts/ui/music_app/views/immersive/music_app_immersive_3d_player.gd`
   - 已新增，负责独立 3D 场景的 demo 频谱、demo 歌单、歌单切换、播放状态和 Mineradio/City 模式切换。

## 阶段计划

### 1. 音频分析基础

状态：已完成 MVP。

任务：

1. [已完成] 在播放 Bus 上添加 `AudioEffectSpectrumAnalyzer`。
2. [已完成] 新增 `MusicAppSpectrumController`。
3. [已完成] 输出稳定参数：
   - `bass`
   - `mid`
   - `treble`
   - `volume`
   - `beat_strength`
   - `beat_detected`
4. [已完成] 对频谱值做平滑，避免视觉抖动。
5. [待做] 用 debug 面板或临时 Label 显示频谱数值。

验收：

1. 播放音乐时 bass/mid/treble 会随音乐变化。
2. 静音或暂停时数值会自然回落。
3. 鼓点检测不会在安静段频繁误触发。

### 2. 基础粒子律动

状态：已完成 MVP。

任务：

1. [已完成] 新增 `music_app_visualizer.tscn`。
2. [已完成] 添加 `GPUParticles3D` 作为主粒子层。
3. [已完成] 用低频控制发射量、速度、粒子尺寸。
4. [已完成] 用中高频控制颜色、亮度、扩散范围。
5. [已完成 MVP] 播放暂停时切换粒子运动状态。

验收：

1. 音乐播放时粒子明显律动。
2. 暂停时粒子减弱或进入慢速 idle。
3. 不影响现有播放器 UI 操作。

### 3. 沉浸式播放器背景接入

状态：部分完成。

任务：

1. [已完成] 将 3D 可视化场景接入 `music_app_showcase_scene.tscn`。
2. [已完成] 保持现有 Control UI 在前景。
3. [已完成 MVP] 增加普通模式/沉浸模式开关。
4. [待做] 可视化加载失败时回退到普通背景。

验收：

1. 主播放器可显示 3D 背景。
2. 弹窗、按钮、播放控制仍可正常点击。
3. 可一键关闭视觉效果。

### 4. 鼓点事件系统

状态：已完成 MVP。

任务：

1. [已完成] 在 `MusicAppSpectrumController` 中实现 kick/beat 检测。
2. [已完成] 发出统一信号：
   - `beat_detected(strength: float)`
   - `spectrum_changed(bass: float, mid: float, treble: float)`
3. [已完成 MVP] 鼓点触发：
   - Bloom/灯光闪光
   - 相机轻微运动
   - 粒子增强
   - 声波环扩散

验收：

1. 重鼓点时能看到明确视觉反馈。
2. 连续鼓点不会导致画面过闪或眩晕。
3. 鼓点事件可以被多个视觉节点复用。

### 5. 声波扩散效果

状态：已完成 MVP。

任务：

1. [已完成 MVP] 新增预铺声波环节点。
2. [已完成] 鼓点时启用透明 emission 圆环。
3. [已完成] 使用脚本插值放大并淡出。
4. [已完成] 根据 `beat_strength` 控制半径、亮度和速度。
5. [待做] 拆出独立 `ShockwaveRing3D` 脚本或子场景，便于复用。

验收：

1. 鼓点触发声波环从中心或城市核心扩散。
2. 多个声波环可叠加但不明显掉帧。
3. 效果可以在低性能档位关闭。

### 6. 流体城市 / 体素地形原型

状态：已完成 MultiMesh 与 City 场景层次 MVP。

任务：

1. [已完成 MVP] 使用 `MultiMeshInstance3D` 创建 16x16 / 24x24 / 32x32 柱阵。
2. [已完成 MVP] 低频控制中心建筑高度。
3. [已完成 MVP] 中频控制周边建筑高度。
4. [已完成 MVP] 高频控制边缘灯光闪烁。
5. [已完成 MVP] 加入 Bloom、emission 材质和相机运动。
6. [已完成 MVP] 增加雾效、地面、道路光带和更明确的科幻城市层次。

验收：

1. 城市柱阵会随音乐起伏。
2. 鼓点时城市泛光明显增强。
3. 默认配置在目标平台保持可接受帧率。

### 7. 性能档位

状态：已完成 MVP。

任务：

1. [已完成] 增加视觉性能档位：
   - Off
   - Low
   - Medium
   - High
2. [部分完成] 档位控制：
   - [已完成] 粒子数量
   - [已完成] 城市网格尺寸
   - [已完成] Bloom 强度
   - [待做] 声波环数量
   - [待做] 更新频率
3. [已完成] Android/iOS/Web 默认 Low。

验收：

1. 切换档位后视觉节点能立即应用。
2. Off 模式不再更新 3D 可视化。
3. 移动端不会默认启用高负载效果。

### 8. 3D 歌单架

状态：已完成交互、封面贴图、舞台层次和 Mineradio 横向玻璃卡 MVP。

任务：

1. [已完成] 新增 `PlaylistShelf3D` 原型。
2. [已完成 MVP] 每个歌单显示为 3D 卡片/唱片盒。
3. [已完成 MVP] 支持左右切换、点击卡片选择、中心卡片播放、当前播放高亮。
4. [部分完成] 使用插值做平滑移动、旋转、缩放；Tween 版本待做。
5. [已完成 MVP] 封面图作为材质贴图，没有封面时使用默认图形。
6. [已完成 MVP] 增加舞台底座、轨道、背景光环和中心高亮。
7. [已完成 MVP] 改成更接近 Mineradio 的横向黑玻璃实体卡。
8. [已完成 MVP] 修复歌单架高度过低、卡片裁切和可见控制按钮覆盖问题。
9. [待做] Tween 版切换动效和点击中心卡片进入详情 polish。

验收：

1. 歌单可在 3D 空间中浏览。
2. 选中歌单后能打开现有歌单详情。
3. 当前播放歌单有清晰的视觉高亮。

### 9. 播放器状态联动

状态：已完成 MVP。

任务：

1. [已完成 MVP] 播放/暂停影响粒子速度和城市亮度。
2. [已完成 MVP] 切歌触发场景过渡。
3. [已完成 MVP] 收藏歌曲触发短粒子反馈。
4. [已完成 MVP] 当前歌曲封面或来源影响视觉主色调。

验收：

1. 视觉状态能反映播放状态。
2. 切歌和收藏反馈不阻塞 UI。
3. 没有封面或数据缺失时有默认表现。

### 10. 设置页接入

状态：已完成 MVP。

任务：

1. [已完成] 在设置数据中增加视觉配置。
2. [已完成 MVP] 设置页增加：
   - 视觉效果开关
   - 视觉模式
   - 性能档位
   - Bloom 强度
   - 粒子强度
   - 粒子强度和 Bloom 强度当前百分比
3. [已完成] 设置变更后立即生效并保存。

验收：

1. 关闭后重启仍保持关闭。
2. 修改档位后视觉效果和性能参数同步变化。

## 推荐里程碑

1. [已完成] 第 1 周：音频频谱 + 粒子律动 MVP。
2. [已完成 MVP] 第 2 周：鼓点闪光 + 声波扩散 + 沉浸背景接入。
3. [已完成 MVP] 第 3 周：流体城市 / 体素地形原型。
4. [部分完成] 第 4 周：3D 歌单架 + 设置页 + 性能优化。

## 首个实施切入点

优先实现 `MusicAppSpectrumController`。它是后续粒子、声波、城市和歌单舞台的统一输入源。没有稳定的频谱数据之前，不建议先堆视觉节点。

当前首个切入点已完成，设置页接入、设置数值显示、性能档位、移动端默认策略、播放状态联动、收藏反馈、歌曲主色调联动、MultiMesh 体素城市、3D 歌单架交互与封面贴图、3D 歌单架 Mineradio 横向玻璃卡与布局修复、独立沉浸式 3D 播放器场景、视觉资源释放、城市独立模式均已完成。下一实施切入点改为：把独立 3D 场景接入真实播放数据，并逐步合并为同一个 3D WorldRoot。
