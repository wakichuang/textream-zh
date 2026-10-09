"""突變檢查：故意弄壞編輯與播放位置互換的每一項規則，確認 verify-position 會變紅。

用法：python3 zh/verify-position/mutations.py
每一項都要讓 run.sh 失敗才算有測試守著；有任何一項還是全綠，結束碼為 1。
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent.parent / 'Textream' / 'Textream' / 'EditorPlaybackPosition.swift'

MUTATIONS = [
    ('游標前面連空白一起算', "let before = text.substring(to: caret).reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }",
     "let before = text.substring(to: caret).count"),
    ('游標在最後面時停在結尾', '        return 0\n    }\n\n    /// 播放停下',
     '        return offset\n    }\n\n    /// 播放停下'),
    ('游標位置用字數不用 UTF-16', 'utf16 += character.utf16.count', 'utf16 += 1'),
    ('停下的位置不跳過空白', "let read = script.prefix(max(0, scriptOffset)).reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }",
     "let read = script.prefix(max(0, scriptOffset)).count"),
    ('對齊到下一個字而不是所在的字', 'if before < seen + word.count { return offset }', 'if before <= seen { return offset }'),
]

original = SRC.read_text(encoding='utf-8')
unguarded = 0
for name, before, after in MUTATIONS:
    assert original.count(before) == 1, f'找不到要突變的程式碼：{name}'
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(SRC, tmp)
        target = pathlib.Path(tmp) / SRC.name
        target.write_text(original.replace(before, after), encoding='utf-8')
        result = subprocess.run([str(HERE / 'run.sh'), tmp], capture_output=True, text=True)
    red = result.returncode != 0
    if not red:
        unguarded += 1
    print(f"{'✅ 變紅' if red else '❌ 還是全綠'}  {name}")

print('每一項都有測試守著' if unguarded == 0 else f'有 {unguarded} 項沒有測試守著')
sys.exit(1 if unguarded else 0)
