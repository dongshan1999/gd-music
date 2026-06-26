# 主提示

1. **UI 预制体**  
   所有 UI 必须落实到预制体（场景文件）中。

2. **弹窗命名与结构规范**
   - 命名必须统一：
     - 预制体：`{前缀}_page`
     - View 脚本：`{前缀}_view`
     - Controller 脚本：`{前缀}_controller`
   - 每个弹窗 **必须** 包含 View 与 Controller。
   - Controller 只能在 View 脚本内部实例化。

3. **存档容错**  
   当前阶段无需对存档功能做任何容错处理。

4. **多语言文本**
   - 所有显示文本统一使用 `translations/music_app.csv`。
   - **脚本中**：使用 `tr()` 或 `DX.localization.bind_text`。
   - **预制体静态文本**：不要硬编码文本，使用 `localize_comp.gd` 填充对应的 key。
5. **代码规范**
   - 新增功能必须遵循 **最小开放接口** 原则，禁止出现无实际逻辑的两层空转发。
   - 所有数值、字符串硬编码必须提取为常量。

# 开发需求
去除 dx debug controller 和 view 重写
1. 使用dx manager 系统新增debug manager
2. debug ui 我希望是动态加载
   1. 比如我创建一个方法 方法上标记@一个特性，就显示一个按钮，
   2. 分组和名称都是一样通过标记特性实现
   3. 目前先实现方法和字符串，数字
  