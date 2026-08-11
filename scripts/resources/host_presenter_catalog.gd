class_name HostPresenterCatalog
extends Resource
## Every selectable Host voice, as data. Mirrors HostCatalog/TutorialHintCatalog's
## shape for the same reason: the list of presenters is content, not code.

@export var presenters: Array[HostPresenter] = []


func find(id: StringName) -> HostPresenter:
	for presenter: HostPresenter in presenters:
		if presenter != null and presenter.id == id:
			return presenter
	return null
