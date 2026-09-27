#!/usr/bin/env python3
"""检查界面文案覆盖率及格式占位符。"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT / 'Ice/Localizable.xcstrings').read_text())
strings = catalog['strings']
errors = []
languages = re.findall(r'case \w+ = "([^"]+)"', (ROOT / 'Ice/Utilities/AppLanguage.swift').read_text())

for key, entry in strings.items():
    for language in languages:
        unit = entry.get('localizations', {}).get(language, {}).get('stringUnit', {})
        value = unit.get('value', '')
        if not value or unit.get('state') != 'translated':
            errors.append(f'{language} 缺失翻译：{key}')
        if sorted(re.findall(r'%(?:@|lld|ld|d|f)', key)) != sorted(re.findall(r'%(?:@|lld|ld|d|f)', value)):
            errors.append(f'{language} 占位符不一致：{key}')

literal = r'"((?:\\.|[^"\\])*)"'
ui_call = re.compile(
    r'(?:\b(?:Text|Button|Toggle|Picker|IcePicker|IceSection|IceMenu|IceLabeledContent|LocalizedStringKey)'
    r'\s*\(\s*|\.(?:annotation|help|alert)\s*\(\s*|'
    r'\bString\s*\(\s*localized:\s*|\.accessibilityAction\(named:\s*)' + literal
)

def check_key(raw, path):
    raw = re.sub(r'\\\([^)]*\)', '%@', raw)
    key = json.loads('"' + raw + '"')
    if key and key not in strings:
        errors.append(f'{path.relative_to(ROOT)} 未翻译：{key}')

for path in (ROOT / 'Ice').rglob('*.swift'):
    text = path.read_text()
    for match in ui_call.finditer(text):
        check_key(match.group(1), path)

# 这些枚举的键由运行时转换，编译器不会自动提取。
for name in ('SettingsNavigationIdentifier', 'ControlItemImageSet', 'RehideStrategy',
             'IceBarLocation', 'MenuBarTintKind', 'SystemAppearance'):
    path = next((ROOT / 'Ice').rglob(name + '.swift'))
    for match in re.finditer(r'case\s+\.?(?:\w+)\s*(?:=|:)\s*' + literal, path.read_text()):
        check_key(match.group(1), path)

if errors:
    raise SystemExit('\n'.join(errors))
print(f'通过：{len(strings)} 条多语言资源，界面文案覆盖及占位符一致。')
