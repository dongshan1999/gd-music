# 主提示
1. UI铺设需要落实到预制体中
2. 弹窗需要保持预制体名称，view脚本，controller脚本名称前缀相同，然后预制体名称 + _page，view脚本 + _view，controller脚本 + _controller，弹窗必须要有view和controller，并且controller只能在view中new
3. 当前开发阶段，存档无须容错处理
4. 文本显示内容都要使用多语言translations/music_app.csv，脚本上直接使用tr或者DX.localization.bind_text，预制体上组件还是使用内容，如果是硬编码不是代码控制使用localize_comp.gd填充key
# 开发需求
1. ![1](12545f6411ae900ac14170881406ae7c.jpg)
2. ![2](c60eac100aec20cf59d9d3528ff4f2ad.jpg)
3. 需要在scripts\ui\music_app\views\settings中新增铺设插件管理界面如图1其内容需要是动态生成预制体，然后图片中卸载插件是放在底部的，我希望和切换按钮放一起，图片使用X表示卸载，还有界面右下方有一个+图片是打开图二，
4. 图二希望铺设在插件管理界面里，然后帮我汇总一下插件对应方法在哪里告诉我