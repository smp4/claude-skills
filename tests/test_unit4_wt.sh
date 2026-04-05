#!/usr/bin/env bash
# Unit 4 tests: afb wt create|list|clean

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AFB="${REPO}/afb"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Create a temp git repo for worktree tests
setup_git_repo() {
  TMP="$(mktemp -d)"
  GIT_REPO="${TMP}/repo"
  mkdir -p "$GIT_REPO"
  git -C "$GIT_REPO" init -b main >/dev/null 2>&1
  git -C "$GIT_REPO" config user.email "test@test.com"
  git -C "$GIT_REPO" config user.name "Test"
  # Need at least one commit for worktrees to work
  echo "init" > "${GIT_REPO}/init.txt"
  git -C "$GIT_REPO" add init.txt
  git -C "$GIT_REPO" commit -m "init" >/dev/null 2>&1

  ACCOUNTS_FILE="${TMP}/accounts.json"
  cat > "$ACCOUNTS_FILE" <<EOF
{
  "accounts": [
    { "name": "test", "claude_home": "${TMP}/claude_home", "default": true }
  ]
}
EOF
  mkdir -p "${TMP}/claude_home"
}

run_afb() {
  (cd "$GIT_REPO" && AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" bash "$AFB" "$@")
}

# ---------------------------------------------------------------------------
# test_wt_create_and_list
# ---------------------------------------------------------------------------
test_wt_create_and_list() {
  setup_git_repo
  rc=0
  out=$(run_afb wt create testfeat 2>&1) || rc=$?
  # Verify worktree directory created
  wt_path="${GIT_REPO}/.claude/worktrees/testfeat"
  list_out=$(run_afb wt list 2>&1) || true
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && echo "$list_out" | grep -q "testfeat"; then
    pass "test_wt_create_and_list"
  else
    fail "test_wt_create_and_list (rc=$rc, list_out=$list_out)"
  fi
}

# ---------------------------------------------------------------------------
# test_wt_create_slugifies
# ---------------------------------------------------------------------------
test_wt_create_slugifies() {
  setup_git_repo
  rc=0
  run_afb wt create "My Feature" 2>&1 >/dev/null || rc=$?
  wt_path="${GIT_REPO}/.claude/worktrees/my-feature"
  list_out=$(run_afb wt list 2>&1) || true
  rm -rf "$TMP"
  if echo "$list_out" | grep -q "my-feature"; then
    pass "test_wt_create_slugifies"
  else
    fail "test_wt_create_slugifies (expected my-feature in list: $list_out)"
  fi
}

# ---------------------------------------------------------------------------
# test_wt_create_existing_exits_1
# ---------------------------------------------------------------------------
test_wt_create_existing_exits_1() {
  setup_git_repo
  run_afb wt create testfeat >/dev/null 2>&1
  rc=0
  run_afb wt create testfeat >/dev/null 2>&1 || rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -eq 1 ]]; then
    pass "test_wt_create_existing_exits_1"
  else
    fail "test_wt_create_existing_exits_1 (rc=$rc, expected 1)"
  fi
}

# ---------------------------------------------------------------------------
# test_wt_clean_removes_worktree
# ---------------------------------------------------------------------------
test_wt_clean_removes_worktree() {
  setup_git_repo
  run_afb wt create testfeat >/dev/null 2>&1
  rc=0
  run_afb wt clean testfeat >/dev/null 2>&1 || rc=$?
  list_out=$(run_afb wt list 2>&1) || true
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && ! echo "$list_out" | grep -q "testfeat"; then
    pass "test_wt_clean_removes_worktree"
  else
    fail "test_wt_clean_removes_worktree (rc=$rc, list still has testfeat: $list_out)"
  fi
}

# ---------------------------------------------------------------------------
# test_wt_clean_dirty_warns
# ---------------------------------------------------------------------------
test_wt_clean_dirty_warns() {
  setup_git_repo
  run_afb wt create testfeat >/dev/null 2>&1
  wt_path="${GIT_REPO}/.claude/worktrees/testfeat"
  # Create uncommitted changes
  echo "dirty" > "${wt_path}/dirty.txt"
  rc=0
  out=$(run_afb wt clean testfeat 2>&1) || rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -eq 1 ]] && echo "$out" | grep -qi "uncommitted\|dirty\|force"; then
    pass "test_wt_clean_dirty_warns"
  else
    fail "test_wt_clean_dirty_warns (rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_wt_clean_force_removes_dirty
# ---------------------------------------------------------------------------
test_wt_clean_force_removes_dirty() {
  setup_git_repo
  run_afb wt create testfeat >/dev/null 2>&1
  wt_path="${GIT_REPO}/.claude/worktrees/testfeat"
  echo "dirty" > "${wt_path}/dirty.txt"
  rc=0
  run_afb wt clean testfeat --force >/dev/null 2>&1 || rc=$?
  list_out=$(run_afb wt list 2>&1) || true
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && ! echo "$list_out" | grep -q "testfeat"; then
    pass "test_wt_clean_force_removes_dirty"
  else
    fail "test_wt_clean_force_removes_dirty (rc=$rc)"
  fi
}

# ---------------------------------------------------------------------------
# test_wt_not_in_git_repo_exits_1
# ---------------------------------------------------------------------------
test_wt_not_in_git_repo_exits_1() {
  TMP="$(mktemp -d)"
  NOT_GIT="${TMP}/notgit"
  mkdir -p "$NOT_GIT"
  ACCOUNTS_FILE="${TMP}/accounts.json"
  cat > "$ACCOUNTS_FILE" <<EOF
{ "accounts": [{ "name": "test", "claude_home": "${TMP}/home", "default": true }] }
EOF
  mkdir -p "${TMP}/home"
  rc=0
  # Run wt create from a non-git directory
  out=$(cd "$NOT_GIT" && AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" bash "$AFB" wt create foo 2>&1) || rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -eq 1 ]] && echo "$out" | grep -qi "git\|repo\|not"; then
    pass "test_wt_not_in_git_repo_exits_1"
  else
    fail "test_wt_not_in_git_repo_exits_1 (rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
test_wt_create_and_list
test_wt_create_slugifies
test_wt_create_existing_exits_1
test_wt_clean_removes_worktree
test_wt_clean_dirty_warns
test_wt_clean_force_removes_dirty
test_wt_not_in_git_repo_exits_1

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
