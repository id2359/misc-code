emcc polywa.cpp -o polywa.js \
  -s WASM=1 \
  -s SINGLE_FILE=1 \
  -s EXPORTED_FUNCTIONS="['_main','_set_shape','_next_shape','_prev_shape','_toggle_auto_rotate','_toggle_auto_cycle','_set_rotation_speed','_rotate_manual','_set_render_mode','_get_current_shape','_get_shape_count']" \
  -s EXPORTED_RUNTIME_METHODS="['ccall','cwrap','UTF8ToString']" \
  -O2
