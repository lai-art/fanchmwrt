#!/usr/bin/env python3
"""检查 patches/*.patch 与它们的目标文件行尾是否一致。

背景
----
本仓库 .gitattributes 是 `* -text`，即 git 完全不做行尾转换：工作区是什么
行尾，提交进库就是什么行尾。而厂家带的 patches/*.patch 全是 LF。

在 Windows 上用编辑器或脚本改被 patch 的目标文件，很容易把整个文件变成
CRLF（或反过来）。这时 GNU patch 在 Build/Prepare 阶段会报：

    005-use-ext-warp-code.patch: Hunk #1 FAILED at 12 (different line endings).

这个报错指向的是 patch 文件，而不是被改坏的源文件，非常难定位；更糟的是它
发生在 Build/Prepare，要等前面的包全部编完（约 90 分钟）才会暴露。

所以在构建开始前几秒直接比对一次。检查范围：package/ 下所有
patches/*.patch（含 target/linux 之外的私有包补丁）。

注意：不要用 `grep -q $'\\r'` 判断行尾，Git Bash 下会误报（本次排查中
26 个 LF 补丁被全部误判成 CRLF）。必须按字节判断 b"\\r\\n" in data。

用法：python3 scripts/ci/check-patch-eol.py [仓库根目录]
退出码：0 全部一致；1 存在不一致（CI 应 fail）
"""

import glob
import io
import os
import re
import sys


def eol(data: bytes) -> str:
    """按字节判断行尾类型。"""
    crlf = data.count(b"\r\n")
    lf = data.count(b"\n")
    if crlf == 0:
        return "LF"
    if crlf == lf:
        return "CRLF"
    return "MIXED(%d/%d)" % (crlf, lf)


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."

    # patch 里的目标路径形如 "+++ b/mt_wifi_ap/Makefile"
    # 目标文件在 "包目录/src/" 下（OpenWrt 惯例：Build/Prepare 复制 src/ 后打补丁）
    patterns = [
        "package/**/patches/*.patch",
        "package/**/patches/**/*.patch",
    ]

    checked = 0
    problems = []

    seen = set()
    for pat in patterns:
        for pf in glob.glob(os.path.join(root, pat), recursive=True):
            if pf in seen:
                continue
            seen.add(pf)

            pb = io.open(pf, "rb").read()
            p_eol = eol(pb)
            prefix = pf + " "

            # 一个包可能有多个 patch，各自的目标文件都在同一个 src/ 下
            pkg_dir = os.path.dirname(os.path.dirname(pf))
            src_dir = os.path.join(pkg_dir, "src")

            targets = re.findall(rb"^\+\+\+ b/([^\t\r\n ]+)", pb, re.M)
            for t in targets:
                rel = t.decode("utf-8", "replace")
                tp = os.path.join(src_dir, rel)
                if not os.path.exists(tp):
                    # 大量包的源码是 PKG_SOURCE 下载的，src/ 下没有目标文件（例如
                    # arm-trusted-firmware-mediatek、内核树）。这类 patch 与工作区
                    # 文件无关，不是本检查的对象，直接跳过。只有目标文件确实在
                    # 树内时才比对行尾。
                    continue
                checked += 1
                tb = io.open(tp, "rb").read()
                t_eol = eol(tb)
                if t_eol != p_eol:
                    problems.append((pf, rel, "patch=%s 目标=%s" % (p_eol, t_eol)))

    print("=== 补丁行尾一致性检查 ===")
    print("扫描补丁 %d 个, 目标文件 %d 处" % (len(seen), checked))

    if not problems:
        print("全部一致 ✓")
        return 0

    print("")
    print("发现 %d 处不一致:" % len(problems))
    for pf, rel, why in problems:
        print("  %s" % os.path.relpath(pf, root))
        print("     %s  ->  %s" % (rel, why))
    print("")
    print("修法：把目标文件统一成与 patch 相同的行尾。例如")
    print("  python3 -c \"import io,sys;p=sys.argv[1];b=io.open(p,'rb').read();"
          "io.open(p,'wb').write(b.replace(b'\\r\\n',b'\\n'))\"  <文件>")
    return 1


if __name__ == "__main__":
    sys.exit(main())
