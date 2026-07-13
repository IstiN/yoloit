package main

// Plain-text board snapshot, byte-compatible with _snapshot() in
// lib/core/remote/yoloitd_server.dart.

import (
	"fmt"
	"strings"
)

func boardSnapshot(board *RemoteBoard) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", board.Name)
	b.WriteString("| Panel | Type | Position | Size |\n")
	b.WriteString("|-------|------|----------|------|\n")
	for _, panel := range board.Panels {
		fmt.Fprintf(
			&b,
			"| %s | %s | %s,%s | %sx%s |\n",
			panel.Title,
			panel.Type,
			formatDartFloat(float64(panel.Bounds.X)),
			formatDartFloat(float64(panel.Bounds.Y)),
			formatDartFloat(float64(panel.Bounds.Width)),
			formatDartFloat(float64(panel.Bounds.Height)),
		)
	}
	return b.String()
}
