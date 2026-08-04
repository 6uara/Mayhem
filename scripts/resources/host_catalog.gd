class_name HostCatalog
extends Resource
## Everything the Host can say, as data rather than string literals in gameplay code.
##
## The two lines that existed before this lived inline in MatchDirector, which is
## why there were two: adding a third meant editing a system that has nothing to do
## with commentary. Writing lines is now a content job.

@export var sets: Array[HostLineSet] = []


func find(id: StringName) -> HostLineSet:
	for line_set: HostLineSet in sets:
		if line_set != null and line_set.id == id:
			return line_set
	return null


func get_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for line_set: HostLineSet in sets:
		if line_set != null:
			out.push_back(line_set.id)
	return out
