#!/usr/bin/env bash
#
# scripts/lint/check-source-cycles.sh - シェル source 依存グラフの循環検出
#
# 仕様（02_設計 §3.7）:
#   - list_shell_files を入力にする。
#   - 各ファイルから `^source ...` / `^. ...` 行を抽出して依存先パスを正規化。
#   - `$ROOT_DIR` は scripts/、`$SCRIPT_DIR` はその source 行を持つファイルのディレクトリと解釈する。
#   - awk で DFS して循環を検出（bash 3.2 互換のため連想配列を使わない）。
#   - 循環があれば該当ノードを出力して非 0 終了。
#
set -u

HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/lint/lib/common.sh
. "$HERE/lib/common.sh"

root="$(repo_root)"
[ -n "$root" ] || { log_error "repo root not found"; exit 1; }

files="$(list_shell_files)"
if [ -z "$files" ]; then
    log_info "no shell files to inspect for source cycles"
    exit 0
fi

# エッジ一覧（from<TAB>to、相対パス）を作る。
# from と to は repo root 起点の相対パス。
edges_file="$(mktemp -t mhk_lint_edges.XXXXXX)"
trap 'rm -f "$edges_file"' EXIT

cd "$root" || { log_error "cd $root failed"; exit 1; }

# 行頭の `source ...` または `. ...` を抽出。サブシェル内 source 等は対象外。
# - `^[[:space:]]*` で先頭空白許容
# - `source <path>` / `. <path>` を捕捉
old_ifs="$IFS"
IFS='
'
# shellcheck disable=SC2206
file_list=( $files )
IFS="$old_ifs"

for f in "${file_list[@]}"; do
    # f のディレクトリ（SCRIPT_DIR 相当）。scripts/bin/foo.sh -> scripts/bin
    fdir="${f%/*}"
    # f が scripts/bin/* の場合の ROOT_DIR は scripts/
    # 設計上 ROOT_DIR は scripts/ 起点を採用する（既存 scripts/bin/* がそう使っている）。
    fproot="scripts"

    # source / . で始まる行を抽出
    while IFS= read -r line; do
        # コメント除去
        line="${line%%#*}"
        # 末尾空白除去
        line="$(printf '%s' "$line" | awk '{$1=$1; print}')"
        [ -z "$line" ] && continue

        # 引数（パス）部分を取り出す
        # 形式: `source <arg>` または `. <arg>`
        # awk で 2 番目以降のフィールドを連結（クォート除去は後段）
        arg="$(printf '%s' "$line" | awk '{ $1=""; sub(/^[[:space:]]+/, ""); print }')"
        # クォート除去
        arg="${arg%\"}"; arg="${arg#\"}"
        arg="${arg%\'}"; arg="${arg#\'}"

        # 変数展開
        # $ROOT_DIR / ${ROOT_DIR}: 置換後はリポジトリルート相対（"scripts/..." の形）。
        # $SCRIPT_DIR / ${SCRIPT_DIR}: 置換後もリポジトリルート相対（fdir 自体が "scripts/bin" 等）。
        # 置換が発生した場合は fdir/ を前置せず、そのまま正規化する。
        rewrote=0
        case "$arg" in
            *\$ROOT_DIR*|*\${ROOT_DIR}*|*\$SCRIPT_DIR*|*\${SCRIPT_DIR}*)
                rewrote=1
                ;;
        esac
        arg="${arg//\$ROOT_DIR/$fproot}"
        arg="${arg//\$\{ROOT_DIR\}/$fproot}"
        arg="${arg//\$SCRIPT_DIR/$fdir}"
        arg="${arg//\$\{SCRIPT_DIR\}/$fdir}"

        # 動的に展開できない引数（他の $... を含む）はスキップ。
        case "$arg" in
            *\$*) continue ;;
        esac

        # 解析対象として使うパスを決める。
        #   - 絶対パスはそのまま（リポジトリ外として後段で除外）。
        #   - 置換済み（rewrote=1）はリポジトリルート相対として正規化のみ実施。
        #   - それ以外は f のディレクトリからの相対と解釈。
        case "$arg" in
            /*) target="$arg" ;;
            *)
                if [ "$rewrote" -eq 1 ]; then
                    target_input="$arg"
                else
                    target_input="$fdir/$arg"
                fi
                # awk による正規化（.. を解決）
                target="$(
                    printf '%s\n' "$target_input" | awk '
                    {
                        n = split($0, parts, "/")
                        m = 0
                        for (i = 1; i <= n; i++) {
                            p = parts[i]
                            if (p == "" || p == ".") continue
                            if (p == "..") { if (m > 0) m-- ; continue }
                            m++
                            out[m] = p
                        }
                        s = ""
                        for (i = 1; i <= m; i++) s = s (i == 1 ? "" : "/") out[i]
                        print s
                    }')"
                ;;
        esac

        # target がリポジトリ外（絶対パスかつ root 外）の場合はスキップ。
        case "$target" in
            /*) continue ;;
        esac

        # target が存在するかは問わない（解析対象としてエッジに加える）。
        # 解析対象に含まれていない外部依存もエッジに残すが、DFS は対象セット内で評価する。
        printf '%s\t%s\n' "$f" "$target" >> "$edges_file"
    done < <(grep -E '^[[:space:]]*(source|\.)[[:space:]]+' "$f" 2>/dev/null || true)
done

# DFS で循環を検出（awk）。
# 入力: edges_file（from<TAB>to の行）
# 解析対象集合: file_list（list_shell_files の結果）
nodes_file="$(mktemp -t mhk_lint_nodes.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -f '$edges_file' '$nodes_file'" EXIT
printf '%s\n' "${file_list[@]}" > "$nodes_file"

cycle_output="$(
    awk -v nodesfile="$nodes_file" '
    BEGIN {
        # 解析対象ノード集合を読む
        while ((getline n < nodesfile) > 0) {
            nodeset[n] = 1
        }
        close(nodesfile)
    }
    {
        from = $1
        to = $2
        # 解析対象集合に含まれるノード間のエッジのみ DFS で扱う
        if (!(from in nodeset)) next
        if (!(to in nodeset)) next
        adj[from] = adj[from] " " to " "
        # ノードを記録
        seen[from] = 1
        seen[to] = 1
    }
    function dfs(u,    i, neigh, t, j, path_str, w, cyc_start) {
        color[u] = 1  # gray
        stack_idx++
        stack[stack_idx] = u
        # adj[u] は " a  b  c " の形（前後にスペース）
        nlist = split(adj[u], neigh, " ")
        for (i = 1; i <= nlist; i++) {
            t = neigh[i]
            if (t == "") continue
            if (color[t] == 0) {
                if (dfs(t)) return 1
            } else if (color[t] == 1) {
                # 循環検出。t から stack 末端までを出力。
                cyc_start = 0
                for (j = 1; j <= stack_idx; j++) {
                    if (stack[j] == t) { cyc_start = j; break }
                }
                path_str = ""
                for (j = cyc_start; j <= stack_idx; j++) {
                    path_str = path_str stack[j] " -> "
                }
                path_str = path_str t
                print "CYCLE: " path_str
                return 1
            }
        }
        color[u] = 2  # black
        stack_idx--
        return 0
    }
    END {
        for (u in seen) {
            if (color[u] == 0) {
                if (dfs(u)) { exit 1 }
            }
        }
        exit 0
    }
    ' "$edges_file"
)"
awk_rc=$?

if [ $awk_rc -ne 0 ]; then
    log_error "source 依存に循環を検出しました"
    printf '%s\n' "$cycle_output" >&2
    exit 1
fi

log_info "source 依存に循環は検出されませんでした"
exit 0
