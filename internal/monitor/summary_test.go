package monitor

import "testing"

func TestShortSummaryEmpty(t *testing.T) {
	if got := ShortSummary("  \n  ", 48); got != "" {
		t.Fatalf("got %q", got)
	}
}

func TestShortSummaryFirstLine(t *testing.T) {
	got := ShortSummary("第一行任务\n第二行不要", 48)
	if got != "第一行任务" {
		t.Fatalf("got %q", got)
	}
}

func TestShortSummaryCollapseSpace(t *testing.T) {
	got := ShortSummary("修   登录\t超时", 48)
	if got != "修 登录 超时" {
		t.Fatalf("got %q", got)
	}
}

func TestShortSummaryTruncate(t *testing.T) {
	in := "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十"
	got := ShortSummary(in, 10)
	if got != "一二三四五六七八九…" {
		t.Fatalf("got %q", got)
	}
	if []rune(got)[len([]rune(got))-1] != '…' {
		t.Fatalf("expected ellipsis, got %q", got)
	}
}

func TestPreferMessageKeepsSummary(t *testing.T) {
	prev := "整理通知里的提示词"
	if got := preferMessage(prev, "stopped"); got != prev {
		t.Fatalf("got %q", got)
	}
	if got := preferMessage(prev, "task_complete"); got != prev {
		t.Fatalf("got %q", got)
	}
	if got := preferMessage("", "permission request"); got != "permission request" {
		t.Fatalf("got %q", got)
	}
	if got := preferMessage(prev, "新的任务摘要"); got != "新的任务摘要" {
		t.Fatalf("got %q", got)
	}
}
