@tool
class_name ValidationIssue
extends RefCounted
## One problem found in an arena. `code` is what tests assert on; `message` is
## what the designer reads; `cell` is where the panel sends the camera.

enum Severity { ERROR, WARNING }

var severity: Severity = Severity.ERROR
var message: String = ""
var cell: Vector3i = Vector3i.ZERO
var code: StringName = &""


static func make(code: StringName, severity: Severity, message: String,
		cell: Vector3i = Vector3i.ZERO) -> ValidationIssue:
	var issue := ValidationIssue.new()
	issue.code = code
	issue.severity = severity
	issue.message = message
	issue.cell = cell
	return issue


func is_error() -> bool:
	return severity == Severity.ERROR
