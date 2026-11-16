# score_popup.gd
# Floating "+100"-style score popup shown at a world position. Instantiated
# directly from code (no dedicated scene), mirroring ExplosionBurst: it rises
# a short distance, fades out over half a second, and frees itself.

extends Node2D

const RISE_DISTANCE: float = 36.0
const DURATION: float = 0.5

var _label: Label


func _init(popup_text: String = "+0", color: Color = Color.WHITE) -> void:
	_label = Label.new()
	_label.text = popup_text
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_font_size_override("font_size", 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(-40.0, -12.0)
	_label.size = Vector2(80.0, 24.0)
	add_child(_label)


func _ready() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE_DISTANCE, DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_label, "modulate:a", 0.0, DURATION).set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(queue_free)
