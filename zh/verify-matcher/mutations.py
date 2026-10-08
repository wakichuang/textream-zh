"""突變檢查：故意拿掉新版的每一項機制，確認 verify-matcher 會變紅。

用法：python3 zh/verify-matcher/mutations.py
每一項都要「至少一條測試變紅」才算有測試守著；有任何一項全綠，結束碼為 1。
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent.parent / 'Textream' / 'Textream'

MUTATIONS = [
    ('拿掉找回位置', 'ZhPromptMatcher.swift',
     'guard firstUnit >= 0, spoken.count >= Self.anchorBaseRun else { return nil }',
     'guard false, firstUnit >= 0, spoken.count >= Self.anchorBaseRun else { return nil }'),
    ('拿掉防拖走', 'ZhPromptMatcher.swift',
     'if atStart || run >= runNeeded(source[si]) {',
     'if true || atStart || run >= runNeeded(source[si]) {'),
    ('讀音比對改成字完全相同', 'ZhPromptMatcher.swift',
     'case .han: return soundsOverlap(source.sounds, spoken.sounds)',
     'case .han: return source.key == spoken.key'),
    ('讀音比對改成字完全相同（字元層）', 'ZhPromptMatcher.swift',
     '(source.isHan ? soundsOverlap(source.sounds, spoken.sounds) : source.key == spoken.key)',
     'source.key == spoken.key'),
    ('拿掉數字正規化', 'ZhNumbers.swift',
     'guard isNumberWord(cores[i]) else {',
     'guard false, isNumberWord(cores[i]) else {'),
    ('拿掉停頓切句', 'ZhPromptMatcher.swift',
     'guard !fullTranscript.isEmpty else { return }',
     'guard false, !fullTranscript.isEmpty else { return }'),
]

# 「讀音比對」的兩處要一起拿掉才算拿掉
GROUPS = [[0], [1], [2, 3], [4], [5]]

unguarded = 0
for group in GROUPS:
    name = MUTATIONS[group[0]][0]
    with tempfile.TemporaryDirectory() as tmp:
        tree = pathlib.Path(tmp) / 'Textream'
        shutil.copytree(HERE.parent.parent, tree, ignore=shutil.ignore_patterns('.git', 'build'))
        for index in group:
            _, file, old, new = MUTATIONS[index]
            path = tree / 'Textream' / 'Textream' / 'ZhMatching' / file
            text = path.read_text(encoding='utf-8')
            assert text.count(old) == 1, f'{name}：找不到要改的那一行（{old}）'
            path.write_text(text.replace(old, new), encoding='utf-8')
        result = subprocess.run([str(tree / 'zh' / 'verify-matcher' / 'run.sh')], capture_output=True, text=True)
    red = [line.split('|')[1].strip() + '（' + line.split('|')[3].strip() + '）'
           for line in result.stdout.splitlines()
           if line.startswith('|') and line.rstrip().endswith('|') and '❌' in line.split('|')[5]]
    red += [line for line in result.stdout.splitlines() if line.startswith('數字正規化 ❌')]
    if result.returncode == 0:
        unguarded += 1
        print(f'⚠️ {name}：測試全綠，這項沒有測試守著')
    else:
        print(f'✅ {name}：{len(red)} 條變紅 → {"、".join(red[:8])}{" …" if len(red) > 8 else ""}')

sys.exit(1 if unguarded else 0)
