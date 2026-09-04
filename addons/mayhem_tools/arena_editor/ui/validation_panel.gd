@tool
class_name ArenaValidationPanel
extends VBoxContainer
## The problem list. Clicking a row asks the dock to take the camera there, which
## is the difference between a validator and a usable validator.

signal issue_activated(cell: Vector3i)

const ERROR_COLOR := Color("#FF5555")
const WARNING_COLOR := Color("#FFC145")

var _summary: Label
var _list: ItemList
var _cells: Array[Vector3i] = []


func _ready() -> void:
	_summary = Label.new()
	_summary.text = "No arena loaded."
	add_child(_summary)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0.0, 140.0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	add_child(_list)


func show_issues(issues: Array[ValidationIssue]) -> void:
	_cells.clear()
	_list.clear()
	var error_count: int = 0
	for issue: ValidationIssue in issues:
		var index: int = _list.add_item("%s  [%s]" % [issue.message, issue.code])
		_list.set_item_custom_fg_color(index, ERROR_COLOR if issue.is_error() else WARNING_COLOR)
		_cells.append(issue.cell)
		if issue.is_error():
			error_count += 1
	var warning_count: int = issues.size() - error_count
	if issues.is_empty():
		_summary.text = "Arena is valid."
	else:
		_summary.text = "%d error(s), %d warning(s)." % [error_count, warning_count]


# Private

func _on_item_selected(index: int) -> void:
	if index >= 0 and index < _cells.size():
		issue_activated.emit(_cells[index])
