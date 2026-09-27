#!/usr/bin/env python3
"""修复锁定版 CompactSlider 在新版 SwiftUI 中的重载歧义。"""
from pathlib import Path
import sys

packages = Path(sys.argv[1])
source = packages / 'checkouts/CompactSlider/Sources/CompactSlider/ProminentCompactSliderStyle.swift'
old = '''            .background(
                LinearGradient(
                    colors: [lowerColor, upperColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(useGradientBackground && (configuration.isDragging || configuration.isHovering) ? 0.2 : 0)
            )'''
new = old.replace('.background(', '.background {', 1).rsplit(')', 1)[0] + '}'
text = source.read_text()
if old in text:
    source.chmod(source.stat().st_mode | 0o200)
    source.write_text(text.replace(old, new))
    print('已修复 CompactSlider 背景重载歧义。')
elif new in text:
    print('CompactSlider 兼容修复已存在。')
else:
    raise SystemExit('CompactSlider 源码与锁定版本不符，请检查兼容修复。')
