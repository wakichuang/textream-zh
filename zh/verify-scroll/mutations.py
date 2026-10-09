"""突變檢查：故意弄壞滾輪逐行跳轉的每一項規則，確認 verify-scroll 會變紅。

用法：python3 zh/verify-scroll/mutations.py
每一項都要讓 run.sh 失敗才算有測試守著；有任何一項還是全綠，結束碼為 1。
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent.parent / 'Textream' / 'Textream' / 'WheelLineJump.swift'

MUTATIONS = [
    ('不換行，留在原地', 'let target = max(0, min(rows.count - 1, current + lines))',
     'let target = max(0, min(rows.count - 1, current))'),
    ('不擋最後一行', 'let target = max(0, min(rows.count - 1, current + lines))',
     'let target = max(0, current + lines)'),
    ('方向反了', 'return deltaY > 0 ? -lines : lines', 'return deltaY > 0 ? lines : -lines'),
    ('觸控板不累積', 'pending += deltaY //', 'pending = deltaY //'),
    ('滑鼠小量不算一格', 'let lines = max(1, Int(abs(deltaY).rounded()))',
     'let lines = Int(abs(deltaY).rounded())'),
    ('同一行不合併', 'abs(last.y - y) <= 2', 'abs(last.y - y) <= 0'),
    ('字元位置不算空白', '$0 + $1.count + 1', '$0 + $1.count'),
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
