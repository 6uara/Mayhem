extends GutTest
## A casing is cosmetic and short-lived. It settles well before its lifetime runs
## out, and settling used to stop the clock - so every casing of the run stayed in
## the viewmodel forever.


func test_a_settled_casing_is_still_freed_when_its_lifetime_ends() -> void:
	var shell: EjectedShell = load("res://scenes/vfx/ejected_shell.tscn").instantiate()
	add_child_autofree(shell)
	shell.eject(Vector3.RIGHT, Vector3.UP)
	# Past the settle drop, well inside the lifetime.
	for _i: int in 20:
		shell._process(0.05)
	assert_true(shell._settled, "precondition: it has landed")
	assert_false(shell.is_queued_for_deletion(), "and it is still on screen for now")

	for _i: int in 40:
		shell._process(0.05)
	assert_true(shell.is_queued_for_deletion(), "a landed casing still goes away")
