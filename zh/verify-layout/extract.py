import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read().split('\n')
def idx(m): return next(i for i,l in enumerate(s) if l.startswith(m))
a=idx('// MARK: - Teleprompter'); b=idx('// MARK: - Word Flow Layout'); c=idx('// MARK: - Elapsed Time')
out='\n'.join(s[:a]+s[b:c])
out=out.replace('private func buildLines','func buildLines').replace('private func buildItems','func buildItems')
open(sys.argv[2],'w',encoding='utf-8').write(out)
