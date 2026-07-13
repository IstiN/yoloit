package main

// State-only panel action dispatch, mirroring handleRemotePanelAction from
// lib/core/remote/yoloitd_panel_actions.dart. Every action here is a pure
// JSON state transform — none of them spawn processes or touch the native
// host (process-running lives behind /api/runs and /api/terminals in
// yoloitd, which are out of scope for yoloit-hub).
//
// Conscious deviation: board.ui actions are NOT ported. They depend on
// UiViewBindings/UiViewPluginBase (tree resolution, storage seeding, text
// extraction) which is far beyond a thin state transform, so every board.ui
// action returns Dart's unsupported-action envelope:
// {"ok": false, "message": "Unknown action: <action>"} with HTTP 400.

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// panelActionResult mirrors RemotePanelActionResult.
type panelActionResult struct {
	ok          bool
	message     *string
	data        map[string]any
	stateUpdate map[string]any
}

// toJSON mirrors RemotePanelActionResult.toJson({panel}).
func (r panelActionResult) toJSON(panel *RemotePanel) map[string]any {
	m := map[string]any{"ok": r.ok}
	if r.message != nil {
		m["message"] = *r.message
	}
	if len(r.data) > 0 {
		m["data"] = r.data
	}
	if len(r.stateUpdate) > 0 {
		m["stateUpdate"] = r.stateUpdate
	}
	if panel != nil {
		m["panel"] = panel
	}
	return m
}

func dataResult(data map[string]any) panelActionResult {
	return panelActionResult{ok: true, data: data}
}

func stateResult(update map[string]any) panelActionResult {
	return panelActionResult{ok: true, stateUpdate: update}
}

func messageResult(message string) panelActionResult {
	return panelActionResult{ok: false, message: &message}
}

// missingResult mirrors _missing.
func missingResult(field string) panelActionResult {
	return messageResult("Missing \"" + field + "\"")
}

// notFoundResult mirrors _notFound.
func notFoundResult(entity string) panelActionResult {
	return messageResult(entity + " not found")
}

// unknownResult mirrors _unknown.
func unknownResult(action string) panelActionResult {
	return messageResult("Unknown action: " + action)
}

// handleRemotePanelAction mirrors the Dart function of the same name.
func handleRemotePanelAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	if panel.Type == "board.ui" {
		// See the file header: board.ui needs UiViewBindings, out of scope.
		return unknownResult(action)
	}
	if action == "get" {
		return dataResult(panelContent(panel))
	}

	switch panel.Type {
	case "board.note.markdown":
		return noteAction(panel, action, args)
	case "board.sticky":
		return stickyAction(panel, action, args)
	case "board.shape":
		return shapeAction(panel, action, args)
	case "board.kanban":
		return kanbanAction(panel, action, args)
	case "board.checklist":
		return checklistAction(panel, action, args)
	case "board.code.snippet":
		return codeAction(panel, action, args)
	case "board.webpage":
		return webpageAction(panel, action, args)
	case "board.playlist":
		return playlistAction(panel, action, args)
	case "board.files":
		return filesAction(panel, action, args)
	case "board.file.preview":
		return filePreviewAction(panel, action, args)
	case "board.filetree":
		return fileTreeAction(panel, action, args)
	case "board.terminal":
		return terminalAction(panel, action, args)
	case "board.timer":
		return timerAction(panel, action, args)
	case "board.chat":
		return chatAction(panel, action, args)
	case "board.setup_guide":
		return setupGuideAction(panel, action, args)
	case "board.run", "board.run_configs":
		return runAction(panel, action, args)
	case "board.table":
		return tableAction(panel, action, args)
	case "board.calendar":
		return calendarAction(panel, action, args)
	case "board.chart":
		return chartAction(panel, action, args)
	case "board.diff.preview":
		return diffPreviewAction(panel, action, args)
	case "board.yolo_assistant":
		return yoloAssistantAction(panel, action, args)
	case "board.widget.custom":
		return customWidgetAction(panel, action, args)
	default:
		return genericAction(panel, action, args)
	}
}

// panelContent mirrors _content: the normalized per-type content view used
// by action 'get' and data-returning actions.
func panelContent(panel *RemotePanel) map[string]any {
	state := panel.State
	or := func(key string, fallback any) any {
		if value := state[key]; value != nil {
			return value
		}
		return fallback
	}
	switch panel.Type {
	case "board.note.markdown":
		return map[string]any{
			"markdown":   or("markdown", ""),
			"autoHeight": or("autoHeight", false),
		}
	case "board.sticky":
		return map[string]any{
			"text":      or("text", ""),
			"color":     or("color", "#FEF08A"),
			"textColor": or("textColor", "#1F2937"),
			"fontSize":  or("fontSize", 18),
		}
	case "board.shape":
		return map[string]any{
			"shape":           or("shape", "rectangle"),
			"text":            or("text", ""),
			"fillColor":       or("fillColor", "#00000000"),
			"strokeColor":     or("strokeColor", "#93C5FD"),
			"textColor":       or("textColor", "#E2E8F0"),
			"strokeWidth":     or("strokeWidth", 3),
			"textHAlign":      or("textHAlign", "center"),
			"textVAlign":      or("textVAlign", "center"),
			"textOrientation": or("textOrientation", "horizontal"),
		}
	case "board.kanban":
		return map[string]any{"columns": panelColumns(panel), "cards": asMaps(state["cards"])}
	case "board.checklist":
		return map[string]any{"items": asMaps(state["items"])}
	case "board.code.snippet":
		return map[string]any{
			"language": or("language", "plaintext"),
			"code":     or("code", ""),
		}
	case "board.webpage":
		return map[string]any{
			"url":     or("url", ""),
			"title":   or("title", ""),
			"favicon": or("favicon", ""),
		}
	case "board.playlist":
		return map[string]any{
			"tracks":       asMaps(state["tracks"]),
			"currentIndex": intArg(state["currentIndex"], -1),
			"playing":      or("playing", false),
		}
	case "board.files":
		return map[string]any{
			"selectedPath": or("selectedPath", ""),
			"files":        asMaps(state["files"]),
		}
	case "board.file.preview":
		return map[string]any{
			"path":     firstNonNil(state["path"], state["filePath"], ""),
			"filePath": firstNonNil(state["filePath"], state["path"], ""),
		}
	case "board.filetree":
		return map[string]any{
			"rootPath":     or("rootPath", ""),
			"expandedDirs": asStrings(state["expandedDirs"]),
			"selectedFile": or("selectedFile", ""),
		}
	case "board.terminal":
		return map[string]any{"config": asMap(state["config"])}
	case "board.timer":
		return map[string]any{
			"duration":  intArg(state["duration"], 300),
			"remaining": intArg(state["remaining"], 300),
			"isRunning": or("isRunning", false),
			"isPaused":  or("isPaused", false),
			"completed": or("completed", false),
			"label":     or("label", ""),
		}
	case "board.chat":
		return map[string]any{
			"config":     asMap(state["config"]),
			"messages":   asMaps(state["messages"]),
			"configured": or("configured", false),
		}
	default:
		return copyMap(state)
	}
}

func noteAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "set":
		text := firstNonNil(args["text"], args["markdown"], nil)
		if text == nil {
			return missingResult("text or markdown")
		}
		return stateResult(map[string]any{"markdown": dartToString(text)})
	case "append":
		text := args["text"]
		if text == nil {
			return missingResult("text")
		}
		current, _ := panel.State["markdown"].(string)
		next := dartToString(text)
		if current != "" {
			next = current + "\n" + next
		}
		return stateResult(map[string]any{"markdown": next})
	case "wrap":
		return stateResult(map[string]any{"autoHeight": true})
	case "nowrap":
		return stateResult(map[string]any{"autoHeight": false})
	}
	return unknownResult(action)
}

func stickyAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "set":
		update := pickArgs(args, "text", "color", "textColor", "fontSize")
		if len(update) == 0 {
			return missingResult("sticky fields")
		}
		return stateResult(update)
	case "append":
		text := args["text"]
		if text == nil {
			return missingResult("text")
		}
		current, _ := panel.State["text"].(string)
		next := dartToString(text)
		if strings.TrimSpace(current) != "" {
			next = current + "\n" + next
		}
		return stateResult(map[string]any{"text": next})
	case "color":
		color := firstNonNil(args["color"], args["fillColor"], nil)
		textColor := args["textColor"]
		if color == nil && textColor == nil && args["fontSize"] == nil {
			return missingResult("color, textColor, or fontSize")
		}
		update := map[string]any{}
		if color != nil {
			update["color"] = color
		}
		if textColor != nil {
			update["textColor"] = textColor
		}
		if args["fontSize"] != nil {
			update["fontSize"] = args["fontSize"]
		}
		return stateResult(update)
	}
	return unknownResult(action)
}

func shapeAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	if action != "set" {
		return unknownResult(action)
	}
	update := pickArgs(args,
		"shape", "text", "fillColor", "strokeColor", "textColor",
		"strokeWidth", "fontSize", "textHAlign", "textVAlign", "textOrientation")
	if len(update) == 0 {
		return missingResult("shape fields")
	}
	return stateResult(update)
}

func kanbanAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	columns := panelColumns(panel)
	cards := asMaps(panel.State["cards"])
	switch action {
	case "columns":
		return dataResult(map[string]any{"columns": columns})
	case "cards":
		return dataResult(map[string]any{"columns": columns, "cards": cards})
	case "add-column":
		name := trimmedString(args["name"])
		if name == nil {
			return missingResult("name")
		}
		columns = append(columns, *name)
		return panelActionResult{
			ok:          true,
			stateUpdate: map[string]any{"columns": columns},
			data:        map[string]any{"columnIndex": len(columns) - 1},
		}
	case "rename-column":
		idx := columnIndex(columns, firstNonNil(args["columnId"], args["column"], nil))
		name := trimmedString(args["name"])
		if idx < 0 || name == nil {
			return missingResult("columnId/name")
		}
		columns[idx] = *name
		return stateResult(map[string]any{"columns": columns})
	case "remove-column":
		idx := columnIndex(columns, firstNonNil(args["columnId"], args["column"], nil))
		if idx < 0 {
			return notFoundResult("column")
		}
		columns = append(columns[:idx], columns[idx+1:]...)
		kept := make([]map[string]any, 0, len(cards))
		for _, card := range cards {
			old := intArg(card["columnIndex"], columnIndex(columns, card["column"]))
			if old == idx {
				continue
			}
			next := copyMap(card)
			if old > idx {
				next["columnIndex"] = old - 1
			} else {
				next["columnIndex"] = old
			}
			delete(next, "column")
			kept = append(kept, next)
		}
		return stateResult(map[string]any{"columns": columns, "cards": kept})
	case "add-card":
		colIndex := columnIndex(columns, firstNonNil(args["columnId"], args["column"], nil))
		title := trimmedString(args["title"])
		if colIndex < 0 || title == nil {
			return missingResult("columnId/title")
		}
		cardID := nextID("card")
		if args["id"] != nil {
			cardID = dartToString(args["id"])
		}
		card := map[string]any{
			"id":          cardID,
			"title":       *title,
			"description": dartStringOr(args["description"], ""),
			"columnIndex": colIndex,
		}
		if args["color"] != nil {
			card["color"] = args["color"]
		}
		cards = append(cards, card)
		return panelActionResult{
			ok:          true,
			stateUpdate: map[string]any{"cards": cards},
			data:        map[string]any{"cardId": cardID},
		}
	case "move-card":
		var cardID *string
		if args["cardId"] != nil {
			id := dartToString(args["cardId"])
			cardID = &id
		}
		to := columnIndex(columns, firstNonNil(args["to"], args["columnId"], args["column"], nil))
		index := -1
		if cardID != nil {
			index = mapIndexWhere(cards, "id", *cardID)
		}
		if cardID == nil || index < 0 || to < 0 {
			return missingResult("cardId/to")
		}
		next := copyMap(cards[index])
		next["columnIndex"] = to
		delete(next, "column")
		cards[index] = next
		return stateResult(map[string]any{"cards": cards})
	case "remove-card":
		if args["cardId"] == nil {
			return missingResult("cardId")
		}
		cardID := dartToString(args["cardId"])
		cards = filterMaps(cards, "id", cardID)
		return stateResult(map[string]any{"cards": cards})
	case "update-card":
		var cardID *string
		if args["cardId"] != nil {
			id := dartToString(args["cardId"])
			cardID = &id
		}
		index := -1
		if cardID != nil {
			index = mapIndexWhere(cards, "id", *cardID)
		}
		if cardID == nil || index < 0 {
			return notFoundResult("card")
		}
		next := copyMap(cards[index])
		for key, value := range pickArgs(args, "title", "description", "color") {
			next[key] = value
		}
		cards[index] = next
		return stateResult(map[string]any{"cards": cards})
	}
	return unknownResult(action)
}

func checklistAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	items := asMaps(panel.State["items"])
	switch action {
	case "items":
		return dataResult(map[string]any{"items": items})
	case "add":
		if args["text"] == nil {
			return missingResult("text")
		}
		id := nextID("item")
		if args["id"] != nil {
			id = dartToString(args["id"])
		}
		items = append(items, map[string]any{
			"id":   id,
			"text": dartToString(args["text"]),
			"done": false,
		})
		return stateResult(map[string]any{"items": items})
	case "check", "uncheck":
		index := itemIndex(items, args)
		if index < 0 {
			return notFoundResult("item")
		}
		next := copyMap(items[index])
		next["done"] = action == "check"
		items[index] = next
		return stateResult(map[string]any{"items": items})
	case "remove":
		index := itemIndex(items, args)
		if index < 0 {
			return notFoundResult("item")
		}
		items = append(items[:index], items[index+1:]...)
		return stateResult(map[string]any{"items": items})
	case "rename":
		index := itemIndex(items, args)
		text := firstNonNil(args["newText"], args["text"], nil)
		if index < 0 || text == nil {
			return missingResult("index/id/text")
		}
		next := copyMap(items[index])
		next["text"] = dartToString(text)
		items[index] = next
		return stateResult(map[string]any{"items": items})
	}
	return unknownResult(action)
}

func codeAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	if action != "set" {
		return unknownResult(action)
	}
	code := args["code"]
	if code == nil {
		return missingResult("code")
	}
	update := map[string]any{"code": dartToString(code)}
	if args["language"] != nil {
		update["language"] = args["language"]
	}
	return stateResult(update)
}

func webpageAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	if action != "open" {
		return unknownResult(action)
	}
	url := dartStringPtr(args["url"])
	if url == nil || *url == "" {
		return missingResult("url")
	}
	update := map[string]any{"url": *url}
	if args["title"] != nil {
		update["title"] = args["title"]
	}
	return stateResult(update)
}

func playlistAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	tracks := asMaps(panel.State["tracks"])
	switch action {
	case "list":
		return dataResult(panelContent(panel))
	case "add":
		path := firstNonNil(args["path"], args["url"], nil)
		if path == nil {
			return missingResult("path or url")
		}
		pathStr := dartToString(path)
		title := lastPathSegment(pathStr)
		if args["title"] != nil {
			title = dartToString(args["title"])
		}
		tracks = append(tracks, map[string]any{"path": pathStr, "title": title})
		return stateResult(map[string]any{"tracks": tracks})
	case "remove":
		index := intArg(args["index"], -1)
		if index < 0 || index >= len(tracks) {
			return notFoundResult("track")
		}
		tracks = append(tracks[:index], tracks[index+1:]...)
		currentIndex := 0
		if len(tracks) == 0 {
			currentIndex = -1
		}
		return stateResult(map[string]any{"tracks": tracks, "currentIndex": currentIndex})
	case "play":
		if len(tracks) == 0 {
			return notFoundResult("track")
		}
		index := intArg(args["index"], intArg(panel.State["currentIndex"], 0))
		index = clamp(index, 0, len(tracks)-1)
		return stateResult(map[string]any{"currentIndex": index, "playing": true})
	case "pause":
		return stateResult(map[string]any{"playing": false})
	case "stop":
		return stateResult(map[string]any{"playing": false, "currentIndex": 0})
	case "next", "prev":
		if len(tracks) == 0 {
			return notFoundResult("track")
		}
		current := intArg(panel.State["currentIndex"], 0)
		next := 0
		if action == "next" {
			next = (current + 1) % len(tracks)
		} else if current > 0 {
			next = current - 1
		} else {
			next = len(tracks) - 1
		}
		return stateResult(map[string]any{"currentIndex": next, "playing": true})
	}
	return unknownResult(action)
}

func filesAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	files := asMaps(panel.State["files"])
	switch action {
	case "open":
		path := dartStringPtr(args["path"])
		if path == nil {
			return missingResult("path")
		}
		return stateResult(map[string]any{"selectedPath": *path})
	case "add":
		path := dartStringPtr(args["path"])
		if path == nil {
			return missingResult("path")
		}
		id := nextID("file")
		if args["id"] != nil {
			id = dartToString(args["id"])
		}
		name := lastPathSegment(*path)
		if args["name"] != nil {
			name = dartToString(args["name"])
		}
		files = append(files, map[string]any{"id": id, "path": *path, "name": name})
		return stateResult(map[string]any{"files": files})
	case "remove":
		id := dartStringPtr(args["id"])
		path := dartStringPtr(args["path"])
		kept := files[:0]
		for _, file := range asMaps(panel.State["files"]) {
			if valueMatches(file["id"], id) || valueMatches(file["path"], path) {
				continue
			}
			kept = append(kept, file)
		}
		return stateResult(map[string]any{"files": kept})
	case "clear":
		return stateResult(map[string]any{"files": []map[string]any{}})
	}
	return unknownResult(action)
}

func filePreviewAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	if action != "open" {
		return unknownResult(action)
	}
	path := dartStringPtr(args["path"])
	if path == nil {
		return missingResult("path")
	}
	update := map[string]any{"path": *path, "filePath": *path}
	if args["title"] != nil {
		update["title"] = args["title"]
	}
	return stateResult(update)
}

func fileTreeAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	expanded := asStrings(panel.State["expandedDirs"])
	switch action {
	case "list":
		return dataResult(panelContent(panel))
	case "open":
		path := dartStringPtr(args["path"])
		if path == nil {
			return missingResult("path")
		}
		return stateResult(map[string]any{"selectedFile": *path})
	case "expand":
		dir := dartStringPtr(args["dir"])
		if dir == nil {
			return missingResult("dir")
		}
		if !stringContains(expanded, *dir) {
			expanded = append(expanded, *dir)
		}
		return stateResult(map[string]any{"expandedDirs": expanded})
	case "collapse":
		dir := dartStringPtr(args["dir"])
		if dir == nil {
			return missingResult("dir")
		}
		expanded = removeString(expanded, *dir)
		return stateResult(map[string]any{"expandedDirs": expanded})
	case "set-root":
		path := dartStringPtr(args["path"])
		if path == nil {
			return missingResult("path")
		}
		return stateResult(map[string]any{
			"rootPath":     *path,
			"expandedDirs": []string{},
			"selectedFile": "",
		})
	case "refresh":
		return stateResult(map[string]any{"_refreshAt": dartISO(time.Now().UTC())})
	}
	return unknownResult(action)
}

func terminalAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	config := asMap(panel.State["config"])
	switch action {
	case "config":
		return dataResult(map[string]any{"config": config})
	case "set-dir":
		dir := firstNonNil(args["dir"], args["path"], nil)
		if dir == nil {
			return missingResult("dir")
		}
		next := copyMap(config)
		next["workingDir"] = dartToString(dir)
		return stateResult(map[string]any{"config": next})
	case "set-session":
		id := dartStringPtr(args["sessionId"])
		if id == nil {
			return missingResult("sessionId")
		}
		next := copyMap(config)
		next["sessionId"] = *id
		return stateResult(map[string]any{"config": next})
	}
	return unknownResult(action)
}

func timerAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "status":
		return dataResult(panelContent(panel))
	case "set":
		duration := durationArg(firstNonNil(args["duration"], panel.State["duration"], nil))
		update := map[string]any{
			"duration":  duration,
			"remaining": duration,
			"isRunning": false,
			"isPaused":  false,
			"completed": false,
		}
		if args["label"] != nil {
			update["label"] = args["label"]
		}
		return stateResult(update)
	case "start":
		duration := durationArg(firstNonNil(args["duration"], panel.State["duration"], nil))
		update := map[string]any{
			"duration":  duration,
			"remaining": duration,
			"isRunning": true,
			"isPaused":  false,
			"completed": false,
			"lastTick":  time.Now().UnixMilli(),
		}
		if args["label"] != nil {
			update["label"] = args["label"]
		}
		return stateResult(update)
	case "pause":
		return stateResult(map[string]any{"isRunning": false, "isPaused": true})
	case "resume":
		return stateResult(map[string]any{
			"isRunning": true,
			"isPaused":  false,
			"lastTick":  time.Now().UnixMilli(),
		})
	case "reset":
		duration := durationArg(panel.State["duration"])
		return stateResult(map[string]any{
			"remaining": duration,
			"isRunning": false,
			"isPaused":  false,
			"completed": false,
		})
	}
	return unknownResult(action)
}

func chatAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	messages := asMaps(panel.State["messages"])
	switch action {
	case "messages":
		return dataResult(map[string]any{"messages": messages, "total": len(messages)})
	case "send":
		text := firstNonNil(args["text"], args["message"], nil)
		if text == nil {
			return missingResult("text")
		}
		messages = append(messages, map[string]any{
			"role":      "user",
			"content":   dartToString(text),
			"createdAt": dartISO(time.Now().UTC()),
		})
		return stateResult(map[string]any{"messages": messages, "configured": true})
	case "config":
		config := copyMap(asMap(panel.State["config"]))
		for key, value := range asMap(args["config"]) {
			config[key] = value
		}
		for key, value := range pickArgs(args, "provider", "model", "workingDir", "sessionName") {
			config[key] = value
		}
		return panelActionResult{
			ok:          true,
			stateUpdate: map[string]any{"config": config, "configured": true},
			data:        map[string]any{"config": config},
		}
	case "clear":
		return stateResult(map[string]any{"messages": []map[string]any{}})
	case "status":
		return dataResult(map[string]any{"messageCount": len(messages), "isProcessing": false})
	}
	return unknownResult(action)
}

func setupGuideAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	selected := asStrings(panel.State["selectedPackageIds"])
	switch action {
	case "select":
		id := dartStringPtr(args["packageId"])
		if id == nil {
			return missingResult("packageId")
		}
		if !stringContains(selected, *id) {
			selected = append(selected, *id)
		}
		return stateResult(map[string]any{"selectedPackageIds": selected})
	case "unselect":
		id := dartStringPtr(args["packageId"])
		if id == nil {
			return missingResult("packageId")
		}
		selected = removeString(selected, *id)
		return stateResult(map[string]any{"selectedPackageIds": selected})
	case "set-selected":
		return stateResult(map[string]any{"selectedPackageIds": asStrings(args["packageIds"])})
	}
	return unknownResult(action)
}

func runAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "get":
		return dataResult(copyMap(panel.State))
	case "set-group":
		group := dartStringPtr(args["group"])
		if group == nil {
			return missingResult("group")
		}
		return stateResult(map[string]any{"group": *group})
	case "select-session":
		id := dartStringPtr(args["sessionId"])
		if id == nil {
			return missingResult("sessionId")
		}
		return stateResult(map[string]any{"activeSessionId": *id})
	case "clear-session":
		return stateResult(map[string]any{"activeSessionId": nil})
	}
	return unknownResult(action)
}

func tableAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	columns := asMaps(panel.State["columns"])
	rows := asMaps(panel.State["rows"])
	switch action {
	case "get":
		return dataResult(map[string]any{
			"tableId": tableEffectiveID(panel),
			"columns": columns,
			"rows":    rows,
		})
	case "set":
		newColumns := asMaps(args["columns"])
		if len(newColumns) == 0 {
			return missingResult("columns")
		}
		newRows := asMaps(args["rows"])
		for i, row := range newRows {
			newRows[i] = normalizeTableRowInput(row)
		}
		return stateResult(map[string]any{"columns": newColumns, "rows": newRows})
	case "set-id":
		tableID := stringArg(firstNonNil(args["tableId"], args["id"], nil))
		if tableID == nil {
			return missingResult("tableId")
		}
		next := copyMap(panel.State)
		next["tableId"] = *tableID
		return stateResult(next)
	case "add-column":
		id := stringArg(firstNonNil(args["id"], args["columnId"], nil))
		if id == nil {
			return missingResult("id")
		}
		for _, column := range columns {
			if columnID(column) == *id {
				return messageResult("Column already exists: " + *id)
			}
		}
		title := stringArg(firstNonNil(args["title"], args["name"], nil))
		columnTitle := *id
		if title != nil {
			columnTitle = *title
		}
		columnType := "text"
		if t := stringArg(args["type"]); t != nil {
			columnType = *t
		}
		newColumn := map[string]any{"id": *id, "title": columnTitle, "type": columnType}
		if _, ok := args["options"].([]any); ok {
			newColumn["options"] = asStrings(args["options"])
		}
		defaultValue := tableDefaultCellValue(columnType)
		updatedRows := make([]map[string]any, 0, len(rows))
		for _, row := range rows {
			next := copyMap(row)
			next[*id] = defaultValue
			updatedRows = append(updatedRows, next)
		}
		return stateResult(map[string]any{
			"columns": append(columns, newColumn),
			"rows":    updatedRows,
		})
	case "rename-column":
		id := stringArg(firstNonNil(args["id"], args["columnId"], nil))
		title := stringArg(firstNonNil(args["title"], args["name"], nil))
		if id == nil || title == nil {
			return missingResult("id/title")
		}
		index := columnIndexByID(columns, *id)
		if index < 0 {
			return notFoundResult("Column")
		}
		next := copyMap(columns[index])
		next["title"] = *title
		columns[index] = next
		return stateResult(map[string]any{"columns": columns})
	case "remove-column":
		id := stringArg(firstNonNil(args["id"], args["columnId"], nil))
		if id == nil {
			return missingResult("id")
		}
		index := columnIndexByID(columns, *id)
		if index < 0 {
			return notFoundResult("Column")
		}
		columns = append(columns[:index], columns[index+1:]...)
		updatedRows := make([]map[string]any, 0, len(rows))
		for _, row := range rows {
			next := copyMap(row)
			delete(next, *id)
			updatedRows = append(updatedRows, next)
		}
		return stateResult(map[string]any{"columns": columns, "rows": updatedRows})
	case "add-row":
		cellInput := normalizeTableCellInput(args, columns)
		cells := map[string]any{}
		for _, column := range columns {
			id := columnID(column)
			cells[id] = tableCastCellValue(cellInput[id], column["type"])
		}
		newRow := map[string]any{"id": fmt.Sprintf("r-%d", time.Now().UnixMilli())}
		for key, value := range cells {
			newRow[key] = value
		}
		return panelActionResult{
			ok:          true,
			stateUpdate: map[string]any{"rows": append(rows, newRow)},
			data:        map[string]any{"rowId": newRow["id"]},
		}
	case "update-row":
		rowID := stringArg(firstNonNil(args["id"], args["rowId"], nil))
		if rowID == nil {
			return missingResult("id")
		}
		index := mapIndexWhere(rows, "id", *rowID)
		if index < 0 {
			return notFoundResult("Row")
		}
		cellInput := normalizeTableCellInput(args, columns)
		updatedCells := copyMap(rows[index])
		for _, column := range columns {
			id := columnID(column)
			if value, ok := cellInput[id]; ok {
				updatedCells[id] = tableCastCellValue(value, column["type"])
			}
		}
		rows[index] = updatedCells
		return stateResult(map[string]any{"rows": rows})
	case "remove-row":
		rowID := stringArg(firstNonNil(args["id"], args["rowId"], nil))
		if rowID == nil {
			return missingResult("id")
		}
		rows = filterMaps(rows, "id", *rowID)
		return stateResult(map[string]any{"rows": rows})
	case "clear":
		return stateResult(map[string]any{"rows": []map[string]any{}})
	}
	return unknownResult(action)
}

// tableEffectiveID mirrors _tableEffectiveId.
func tableEffectiveID(panel *RemotePanel) string {
	if custom := stringArg(panel.State["tableId"]); custom != nil {
		return *custom
	}
	return panel.ID
}

func columnID(column map[string]any) string {
	id, _ := column["id"].(string)
	return id
}

func columnIndexByID(columns []map[string]any, id string) int {
	for i, column := range columns {
		if columnID(column) == id {
			return i
		}
	}
	return -1
}

// tableCellInput mirrors _tableCellInput.
func tableCellInput(args map[string]any) map[string]any {
	cells := firstNonNil(args["cells"], args["row"], nil)
	if m, ok := cells.(map[string]any); ok {
		return m
	}
	return args
}

// normalizeTableCellInput mirrors _normalizeTableCellInput: cell values keyed
// by column title are remapped to the matching column id; an id key wins.
func normalizeTableCellInput(args map[string]any, columns []map[string]any) map[string]any {
	input := tableCellInput(args)
	columnIDs := map[string]bool{}
	titleToID := map[string]string{}
	for _, column := range columns {
		id := columnID(column)
		columnIDs[id] = true
		if title, ok := column["title"].(string); ok {
			titleToID[strings.ToLower(strings.TrimSpace(title))] = id
		}
	}
	normalized := map[string]any{}
	for key, value := range input {
		if columnIDs[key] {
			normalized[key] = value
			continue
		}
		if id, ok := titleToID[strings.ToLower(strings.TrimSpace(key))]; ok && id != "" {
			normalized[id] = value
			continue
		}
		normalized[key] = value
	}
	return normalized
}

// normalizeTableRowInput mirrors _normalizeTableRowInput.
func normalizeTableRowInput(row map[string]any) map[string]any {
	if cells, ok := row["cells"].(map[string]any); ok {
		normalized := map[string]any{"id": row["id"]}
		for key, value := range cells {
			normalized[key] = value
		}
		return normalized
	}
	return row
}

// tableDefaultCellValue mirrors _tableDefaultCellValue.
func tableDefaultCellValue(columnType string) any {
	switch columnType {
	case "number":
		return 0
	case "date":
		return dartISO(time.Now().UTC())[:10]
	default:
		return ""
	}
}

// tableCastCellValue mirrors _tableCastCellValue.
func tableCastCellValue(value, columnType any) any {
	typeStr, _ := columnType.(string)
	if value == nil {
		return tableDefaultCellValue(typeStr)
	}
	switch typeStr {
	case "number":
		if isNumber(value) {
			return value
		}
		parsed, err := strconv.ParseFloat(dartToString(value), 64)
		if err != nil {
			return dartFloat(0)
		}
		return dartFloat(parsed)
	default:
		return dartToString(value)
	}
}

func calendarAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	events := asMaps(panel.State["events"])
	switch action {
	case "events":
		return dataResult(map[string]any{"events": events, "count": len(events)})
	case "create-event", "add-event":
		title := stringArg(args["title"])
		if title == nil {
			return missingResult("title")
		}
		start := parseOptionalDate(args["start"])
		if start == nil {
			return missingResult("start")
		}
		event := map[string]any{
			"id":          nextID("ev"),
			"title":       *title,
			"start":       dartISO(start.UTC()),
			"end":         isoOrNil(parseOptionalDate(args["end"])),
			"allDay":      truthyArg(args["allDay"]),
			"description": dartStringOr(args["description"], ""),
			"color":       dartStringOr(args["color"], ""),
			"meetingUrl":  dartStringOr(firstNonNil(args["meetingUrl"], args["url"], nil), ""),
		}
		events = append(events, event)
		return panelActionResult{
			ok:          true,
			stateUpdate: map[string]any{"events": events, "eventCount": len(events)},
			data:        map[string]any{"event": event},
		}
	case "update-event":
		eventID := stringArg(firstNonNil(args["eventId"], args["id"], nil))
		if eventID == nil {
			return missingResult("eventId")
		}
		index := mapIndexWhere(events, "id", *eventID)
		if index < 0 {
			return notFoundResult("Event")
		}
		next := copyMap(events[index])
		if _, ok := args["title"]; ok {
			next["title"] = dartStringOr(args["title"], "")
		}
		if _, ok := args["start"]; ok {
			if parsed := parseOptionalDate(args["start"]); parsed != nil {
				next["start"] = dartISO(parsed.UTC())
			}
		}
		if _, ok := args["end"]; ok {
			next["end"] = isoOrNil(parseOptionalDate(args["end"]))
		}
		if _, ok := args["allDay"]; ok {
			next["allDay"] = truthyArg(args["allDay"])
		}
		if _, ok := args["description"]; ok {
			next["description"] = dartStringOr(args["description"], "")
		}
		if _, ok := args["color"]; ok {
			next["color"] = dartStringOr(args["color"], "")
		}
		if _, hasMeetingURL := args["meetingUrl"]; hasMeetingURL {
			next["meetingUrl"] = dartStringOr(args["meetingUrl"], "")
		} else if _, hasURL := args["url"]; hasURL {
			next["meetingUrl"] = dartStringOr(args["url"], "")
		}
		events[index] = next
		return panelActionResult{
			ok:          true,
			stateUpdate: map[string]any{"events": events, "eventCount": len(events)},
			data:        map[string]any{"event": next},
		}
	case "delete-event":
		eventID := stringArg(firstNonNil(args["eventId"], args["id"], nil))
		if eventID == nil {
			return missingResult("eventId")
		}
		events = filterMaps(events, "id", *eventID)
		return stateResult(map[string]any{"events": events, "eventCount": len(events)})
	case "set-view":
		view := stringArg(args["view"])
		allowed := []string{"month", "week", "workWeek", "day", "threeDay", "list"}
		if view == nil || !stringContains(allowed, *view) {
			return messageResult("Invalid view. Allowed: " + strings.Join(allowed, ", "))
		}
		next := copyMap(panel.State)
		next["view"] = *view
		return stateResult(next)
	case "focus-date":
		date := parseOptionalDate(firstNonNil(args["date"], args["focusedDate"], nil))
		if date == nil {
			return missingResult("date")
		}
		only := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.Local)
		next := copyMap(panel.State)
		next["focusedDate"] = dartISO(only.UTC())
		return stateResult(next)
	case "scroll-to-time":
		hour, err := strconv.Atoi(dartToString(args["hour"]))
		if args["hour"] == nil || err != nil || hour < 0 || hour > 23 {
			return missingResult("hour (0-23)")
		}
		next := copyMap(panel.State)
		next["scrollHour"] = hour
		return stateResult(next)
	}
	return unknownResult(action)
}

func chartAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "get":
		return dataResult(map[string]any{
			"type":         orState(panel.State, "type", "line"),
			"data":         orState(panel.State, "data", []map[string]any{}),
			"xKey":         orState(panel.State, "xKey", "month"),
			"yKey":         orState(panel.State, "yKey", "sales"),
			"groupKey":     panel.State["groupKey"],
			"tablePanelId": panel.State["tablePanelId"],
			"animated":     orState(panel.State, "animated", true),
		})
	case "set-data":
		next := copyMap(panel.State)
		next["data"] = asMaps(firstNonNil(args["data"], args["json"], nil))
		return stateResult(next)
	case "set-type":
		chartType := stringArg(args["type"])
		allowed := []string{"line", "bar", "pie", "scatter", "radar", "area"}
		if chartType == nil || !stringContains(allowed, *chartType) {
			return messageResult("Invalid type. Allowed: " + strings.Join(allowed, ", "))
		}
		next := copyMap(panel.State)
		next["type"] = *chartType
		return stateResult(next)
	case "set-options":
		next := copyMap(panel.State)
		if xKey := stringArg(firstNonNil(args["xKey"], args["x"], nil)); xKey != nil {
			next["xKey"] = *xKey
		}
		if yKey := stringArg(firstNonNil(args["yKey"], args["y"], nil)); yKey != nil {
			next["yKey"] = *yKey
		}
		if groupKey := stringArg(firstNonNil(args["groupKey"], args["group"], nil)); groupKey != nil {
			if *groupKey == "" {
				next["groupKey"] = nil
			} else {
				next["groupKey"] = *groupKey
			}
		}
		if animated, ok := args["animated"].(bool); ok {
			next["animated"] = animated
		}
		return stateResult(next)
	case "link-table":
		tablePanelID := stringArg(firstNonNil(args["tablePanelId"], args["table"], nil))
		if tablePanelID == nil {
			return missingResult("tablePanelId")
		}
		next := copyMap(panel.State)
		next["tablePanelId"] = *tablePanelID
		return stateResult(next)
	case "unlink-table":
		next := copyMap(panel.State)
		next["tablePanelId"] = nil
		return stateResult(next)
	case "refresh":
		return panelActionResult{
			ok:      true,
			message: strPtr("Refresh requires board context; state unchanged"),
			data:    map[string]any{"tablePanelId": panel.State["tablePanelId"]},
		}
	}
	return unknownResult(action)
}

func diffPreviewAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "open":
		path := firstNonNil(args["path"], args["filePath"], nil)
		if path == nil {
			return missingResult("path")
		}
		update := map[string]any{"filePath": dartToString(path)}
		if args["title"] != nil {
			update["title"] = args["title"]
		}
		return stateResult(update)
	case "set-root":
		root := firstNonNil(args["rootPath"], args["path"], nil)
		if root == nil {
			return missingResult("rootPath")
		}
		return stateResult(map[string]any{"rootPath": dartToString(root)})
	}
	return unknownResult(action)
}

func yoloAssistantAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "get":
		return dataResult(copyMap(panel.State))
	case "set-mode":
		mode := dartStringPtr(args["mode"])
		if mode == nil {
			return missingResult("mode")
		}
		return stateResult(map[string]any{"mode": *mode})
	case "set-status":
		status := dartStringPtr(args["status"])
		if status == nil {
			return missingResult("status")
		}
		return stateResult(map[string]any{"assistantStatus": *status})
	case "clear":
		return stateResult(map[string]any{
			"messages":      []map[string]any{},
			"voiceDraft":    "",
			"voiceResponse": "",
		})
	}
	return unknownResult(action)
}

func customWidgetAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	switch action {
	case "get":
		return dataResult(copyMap(panel.State))
	case "set-widget":
		widgetID := dartStringPtr(args["widgetId"])
		if widgetID == nil {
			return missingResult("widgetId")
		}
		return stateResult(map[string]any{"widgetId": *widgetID})
	case "set-config":
		config := copyMap(asMap(panel.State["config"]))
		for key, value := range asMap(args["config"]) {
			config[key] = value
		}
		return stateResult(map[string]any{"config": config})
	case "set":
		update := copyMap(args)
		delete(update, "action")
		return stateResult(update)
	}
	return unknownResult(action)
}

func genericAction(panel *RemotePanel, action string, args map[string]any) panelActionResult {
	if action == "set" {
		update := copyMap(args)
		delete(update, "action")
		return stateResult(update)
	}
	return unknownResult(action)
}

// --- shared action helpers (mirror the _-prefixed Dart helpers) ---

// pickArgs mirrors _pick: copy the given keys that are present in args
// (presence only — values may be null).
func pickArgs(args map[string]any, keys ...string) map[string]any {
	out := map[string]any{}
	for _, key := range keys {
		if value, ok := args[key]; ok {
			out[key] = value
		}
	}
	return out
}

func copyMap(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for key, value := range m {
		out[key] = value
	}
	return out
}

// asMap mirrors _map.
func asMap(value any) map[string]any {
	if m, ok := value.(map[string]any); ok {
		return copyMap(m)
	}
	return map[string]any{}
}

// asMaps mirrors _maps: a fresh list of fresh maps from a JSON list.
func asMaps(value any) []map[string]any {
	list, ok := value.([]any)
	if !ok {
		return []map[string]any{}
	}
	out := make([]map[string]any, 0, len(list))
	for _, entry := range list {
		if m, ok := entry.(map[string]any); ok {
			out = append(out, copyMap(m))
		}
	}
	return out
}

// asStrings mirrors _strings.
func asStrings(value any) []string {
	list, ok := value.([]any)
	if !ok {
		return []string{}
	}
	out := make([]string, 0, len(list))
	for _, entry := range list {
		out = append(out, dartToString(entry))
	}
	return out
}

// panelColumns mirrors _columns.
func panelColumns(panel *RemotePanel) []string {
	if list, ok := panel.State["columns"].([]any); ok {
		out := make([]string, 0, len(list))
		for _, entry := range list {
			out = append(out, dartToString(entry))
		}
		return out
	}
	return []string{"Todo", "Doing", "Done"}
}

// columnIndex mirrors _columnIndex.
func columnIndex(columns []string, value any) int {
	if isNumber(value) {
		return int(toInt64(value))
	}
	text := dartStringPtr(value)
	if text == nil {
		return -1
	}
	if parsed, err := strconv.Atoi(*text); err == nil {
		return parsed
	}
	lower := strings.ToLower(*text)
	for i, column := range columns {
		if strings.ToLower(column) == lower {
			return i
		}
	}
	return -1
}

// itemIndex mirrors _itemIndex.
func itemIndex(items []map[string]any, args map[string]any) int {
	if isNumber(args["index"]) {
		return int(toInt64(args["index"]))
	}
	if id := dartStringPtr(args["id"]); id != nil {
		if index := mapIndexWhere(items, "id", *id); index >= 0 {
			return index
		}
	}
	if text := dartStringPtr(args["text"]); text != nil {
		return mapIndexWhere(items, "text", *text)
	}
	return -1
}

// mapIndexWhere finds the first map whose string value at key equals want.
func mapIndexWhere(maps []map[string]any, key, want string) int {
	for i, m := range maps {
		if value, ok := m[key].(string); ok && value == want {
			return i
		}
	}
	return -1
}

// filterMaps drops maps whose string value at key equals want.
func filterMaps(maps []map[string]any, key, want string) []map[string]any {
	out := make([]map[string]any, 0, len(maps))
	for _, m := range maps {
		if value, ok := m[key].(string); ok && value == want {
			continue
		}
		out = append(out, m)
	}
	return out
}

// valueMatches mirrors Dart `file['id'] == id` where id is String?: a nil
// needle matches a missing key.
func valueMatches(value any, needle *string) bool {
	if needle == nil {
		return value == nil
	}
	text, ok := value.(string)
	return ok && text == *needle
}

// intArg mirrors _int.
func intArg(value any, fallback int) int {
	if isNumber(value) {
		return int(toInt64(value))
	}
	if text, ok := value.(string); ok {
		if parsed, err := strconv.Atoi(strings.TrimSpace(text)); err == nil {
			return parsed
		}
	}
	return fallback
}

// durationArg mirrors _duration.
func durationArg(value any) int {
	return clamp(intArg(value, 300), 1, 86400)
}

func clamp(value, low, high int) int {
	if value < low {
		return low
	}
	if value > high {
		return high
	}
	return value
}

// stringArg mirrors _string: trimmed, empty becomes nil.
func stringArg(value any) *string {
	if value == nil {
		return nil
	}
	text := strings.TrimSpace(dartToString(value))
	if text == "" {
		return nil
	}
	return &text
}

// trimmedString mirrors `args['k']?.toString().trim()` with the Dart
// `name == null || name.isEmpty` guard folded in.
func trimmedString(value any) *string {
	return stringArg(value)
}

// dartStringPtr mirrors `args['k']?.toString()`: nil stays nil, no trimming.
func dartStringPtr(value any) *string {
	if value == nil {
		return nil
	}
	text := dartToString(value)
	return &text
}

func dartStringOr(value any, fallback string) string {
	if value == nil {
		return fallback
	}
	return dartToString(value)
}

// firstNonNil returns the first non-nil argument, or fallback.
func firstNonNil(values ...any) any {
	for _, value := range values[:len(values)-1] {
		if value != nil {
			return value
		}
	}
	return values[len(values)-1]
}

func orState(state map[string]any, key string, fallback any) any {
	if value := state[key]; value != nil {
		return value
	}
	return fallback
}

// truthyArg mirrors `value == true || value?.toString().toLowerCase() == 'true'`.
func truthyArg(value any) bool {
	if b, ok := value.(bool); ok {
		return b
	}
	return strings.ToLower(dartToString(value)) == "true"
}

func stringContains(list []string, want string) bool {
	for _, entry := range list {
		if entry == want {
			return true
		}
	}
	return false
}

func removeString(list []string, want string) []string {
	out := make([]string, 0, len(list))
	for _, entry := range list {
		if entry != want {
			out = append(out, entry)
		}
	}
	return out
}

func lastPathSegment(path string) string {
	parts := strings.Split(path, "/")
	return parts[len(parts)-1]
}

// parseOptionalDate mirrors DateTime.tryParse: ISO-8601 with or without a
// timezone (no-zone values are local time, like Dart).
func parseOptionalDate(value any) *time.Time {
	if value == nil {
		return nil
	}
	text := dartToString(value)
	utcLayouts := []string{time.RFC3339Nano, time.RFC3339}
	localLayouts := []string{
		"2006-01-02T15:04:05.999999",
		"2006-01-02T15:04:05",
		"2006-01-02T15:04",
		"2006-01-02 15:04:05",
		"2006-01-02",
	}
	for _, layout := range utcLayouts {
		if parsed, err := time.Parse(layout, text); err == nil {
			return &parsed
		}
	}
	for _, layout := range localLayouts {
		if parsed, err := time.ParseInLocation(layout, text, time.Local); err == nil {
			return &parsed
		}
	}
	return nil
}

func isoOrNil(t *time.Time) any {
	if t == nil {
		return nil
	}
	return dartISO(t.UTC())
}

// dartToString approximates Dart's Object.toString() for JSON values.
func dartToString(value any) string {
	switch v := value.(type) {
	case nil:
		return "null"
	case string:
		return v
	case bool:
		if v {
			return "true"
		}
		return "false"
	case float64:
		return formatDartFloat(v)
	case int64:
		return strconv.FormatInt(v, 10)
	case int:
		return strconv.Itoa(v)
	case fmt.Stringer:
		return v.String()
	default:
		data, err := marshalCompact(value)
		if err != nil {
			return fmt.Sprintf("%v", value)
		}
		return string(data)
	}
}
