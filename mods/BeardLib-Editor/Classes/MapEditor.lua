MapEditor = MapEditor or class()
core:import("CoreEditorWidgets")

local Editor = MapEditor
local Utils = BLE.Utils
local m = {}
function Editor:init()
    managers.editor = self
    if not PackageManager:loaded("core/packages/editor") then
        PackageManager:load("core/packages/editor")
    end

    self._current_script = "default"
    self._current_continent = "world"
    self._grid_size = 1
    self._current_pos = Vector3()
    self._spawn_position = Vector3()
    self._snap_rotation = 90
    self._screen_borders = Utils:GetConvertedResolution()
    self._mul = 80
	self._camera_object = World:create_camera()
    self._camera_object:set_near_range(20)
	self._camera_object:set_far_range(BLE.Options:GetValue("Map/CameraFarClip"))
    self._camera_object:set_fov(BLE.Options:GetValue("Map/CameraFOV"))
	self._camera_object:set_position(Vector3(864, -789, 458))
	self._camera_object:set_rotation(Rotation(54.8002, -21.7002, 8.53774e-007))
	self._vp = managers.viewport:new_vp(0, 0, 1, 1, "MapEditor", 10)
	self._vp:set_camera(self._camera_object)
	self._camera_pos = self._camera_object:position()
	self._camera_rot = self._camera_object:rotation()
    self._editor_all = World:make_slot_mask(1, 10, 11, 15, 19, 29, 34, 35, 36, 37, 38, 39)
	self._con = managers.menu._controller
    self._move_widget = CoreEditorWidgets.MoveWidget:new(self)
    self._rotate_widget = CoreEditorWidgets.RotationWidget:new(self)

    self:set_use_surface_move(BLE.Options:GetValue("Map/SurfaceMove"))
    self:check_has_fix()

    self._idstrings = {
        ["@ID4f01cba97e94239b@"] = "x",
        ["@IDce15c901d9af3e30@"] = "y",
        ["@ID1a99fc522e3faad0@"] = "z",
        ["@IDc126f12c99c8804d@"] = "xy",
        ["@ID5dac81a18d09497c@"] = "xz",
        ["@ID0602a12dbeee9c14@"] = "yz",
    }
    
    self._toggle_trigger = BeardLib.Utils.Input:TriggerDataFromString(BLE.Options:GetValue("Input/ToggleMapEditor"))
    local normal = not Global.editor_safe_mode
    self._menu = MenuUI:new({
        layer = 100,
        scroll_speed = 100,
        allow_full_input = true,
        background_color = Color.transparent,
        accent_color = BLE.Options:GetValue("AccentColor"),
        mouse_press = normal and callback(self, self, "mouse_pressed"),
        mouse_release = normal and callback(self, self, "mouse_released"),
        create_items = callback(self, self, "post_init"),
    })
end

--Who doesn't like a short code :P
function Editor:m() return m end

function Editor:post_init(menu)
    self.parts = m
    m.menu = UpperMenu:new(self, menu)
    m.status = StatusMenu:new(self, menu)
    m.world = WorldDataEditor:new(self, menu)
    m.mission = MissionEditor:new(self, menu)
    m.static = StaticEditor:new(self, menu)
    m.opt = InEditorOptions:new(self, menu)
    m.console = EditorConsole:new(self, menu)
    m.env = EnvEditor:new(self, menu)
    m.instances = InstancesEditor:new(self, menu)
    m.undo_handler = UndoUnitHandler:new(self, menu)
    m.cubemap_creator = CubemapCreator:new(self, menu, self._camera_object)
    for name, manager in pairs(m) do
        manager.manager_name = name
    end

    m.menu:build_tabs()
    m.world:Switch()

    menu.mouse_move = callback(m.static, m.static, "mouse_moved")
    if self._has_fix then
        m.menu:toggle_widget("move")
    end
end

--functions
function Editor:animate_bg_fade()
    if not self._menu then
        return
    end
    
    local bg = self._menu._panel:rect({
        name = "Background",
        layer = 10000,
        color = BLE.Options:GetValue("BackgroundColor"):with_alpha(1),
    })
    play_anim(bg, {
        set = {alpha = 0},
        callback = function(o)
            if alive(o) then
                o:parent():destroy(o)
            end
        end,
        wait = 0.5,
    })
end

function Editor:check_has_fix()
    local unit = World:spawn_unit(Idstring("core/units/move_widget/move_widget"), Vector3())
    self._has_fix = World:raycast("ray", unit:position(), unit:position():with_z(100), "ray_type", "widget", "target_unit", unit) ~= nil
    unit:set_enabled(false)
    unit:set_slot(0)
end

function Editor:update_grid_size(value)
    self._grid_size = tonumber(value)
    for _, manager in pairs(m) do
        if manager.update_grid_size then
            manager:update_grid_size()
        end
    end
end

local dis = mvector3.distance
function Editor:SetRulerPoints()
    local start_pos = self._current_pos    
	if not self._end_pos then
        self._start_pos = start_pos
        self:Log("[RULER]Start position: " .. tostring(start_pos))
    else
        self:Log(string.format("[RULER]Length: %.2fm", dis(self._start_pos, self._end_pos) / 100))
        self:Log("[RULER]End position: " .. tostring(self._end_pos))
        self._end_pos = nil
        self._start_pos = nil
	end
end

function Editor:reset_widget_values()
    self._using_move_widget = false
    self._using_rotate_widget = false
    self._move_widget:reset_values()
    self._rotate_widget:reset_values()
end

function Editor:OnWidgetGrabbed()
    self:StorePreviousPosRot()
    self._old_units = self:selected_units()
end

function Editor:StorePreviousPosRot()
    for _, unit in pairs(self:selected_units()) do
        unit:unit_data()._prev_pos = unit:position()
        unit:unit_data()._prev_rot = unit:rotation()
    end
end

function Editor:OnWidgetReleased()
    local unit = self:selected_unit()
    if alive(self:widget_unit()) then
        if unit:unit_data()._prev_pos ~= self:widget_unit():position() then
            m.undo_handler:SaveUnitValues(self._old_units, "pos")
        end

        if unit:unit_data()._prev_rot ~= self:widget_unit():rotation() then
            m.undo_handler:SaveUnitValues(self._old_units, "rot")
        end
    end
end

function Editor:move_widget_enabled(use)
    return self._move_widget._use
end

function Editor:rotation_widget_enabled(use)
    return self._rotate_widget._use
end

function Editor:toggle_move_widget(use)
    self._move_widget:set_use(not self:move_widget_enabled())
end

function Editor:toggle_rotation_widget()
    self._rotate_widget:set_use(not self:rotation_widget_enabled())
end

function Editor:use_widgets(use)
    use = use and self:enabled()
    self._move_widget:set_enabled(use)
    self._rotate_widget:set_enabled(use)
end

function Editor:mouse_moved(x, y)
    m.static:mouse_moved(x, y)
end

function Editor:mouse_released(button, x, y)
    if self:is_using_widget() then self:OnWidgetReleased() end
    m.static:mouse_released(button, x, y)    
    self:reset_widget_values()
end

function Editor:mouse_pressed(button, x, y)
    if self._menu:MouseInside() then
        return
    end
    if m.world:mouse_pressed(button, x, y) then
        return
    end
    if m.mission:mouse_pressed(button, x, y) then
        return
    end
    m.static:mouse_pressed(button, x, y)
end

function Editor:select_unit(unit, add, switch)
    add = NotNil(add, ctrl())
    m.static:set_selected_unit(unit, add)
    if switch then
        m.static:Switch()
    end
end

function Editor:select_element(element, add, switch)
    add = NotNil(add, ctrl())
    for _, unit in pairs(m.mission:units()) do
        if unit:mission_element() and unit:mission_element().element.id == element.id and unit:mission_element().element.editor_name == element.editor_name then
            self:select_unit(unit, add == true, NotNil(switch, not add))
            break
        end
    end
end

function Editor:DeleteUnit(unit)
    if alive(unit) then
        if unit:mission_element() then 
            managers.mission:delete_element(unit:mission_element().element.id) 
            if managers.editor then
                m.mission:remove_element_unit(unit)
            end
        end
        local ud = unit:unit_data()
        if ud then
            m.world:delete_unit(unit)
            managers.worlddefinition:delete_unit(unit)
        end
        World:delete_unit(unit)
    end
    managers.worlddefinition:check_names()
end

function Editor:GetSpawnPosition(data)
    local position
    if data then
        position = data.position
    end
    return position or (m.world:is_spawning() and self._spawn_position) or self:cam_spawn_pos()
end

function Editor:SpawnUnit(unit_path, old_unit, add, unit_id)
    if m.world:is_world_unit(unit_path) then
        local data = type(old_unit) == "userdata" and old_unit:unit_data() or old_unit and old_unit.unit_data or {}
        data.position = self:GetSpawnPosition(data)
        local unit = m.world:do_spawn_unit(unit_path, data)
        if alive(unit) then self:select_unit(unit, add) end
        return unit
    end
    local data = {}
    local t 
    if type(old_unit) == "userdata" then
        data = {
            unit_data = deep_clone(old_unit:unit_data()),
            wire_data = old_unit:wire_data() and deep_clone(old_unit:wire_data()),
            ai_editor_data = old_unit:ai_editor_data() and deep_clone(old_unit:ai_editor_data()),
        }
        t = old_unit:wire_data() and "wire" or old_unit:ai_editor_data() and "ai" or ""
        data.unit_data.name_id = nil
        data.unit_data.unit_id = unit_id or managers.worlddefinition:GetNewUnitID(data.unit_data.continent or self._current_continent, t)
    else
        t = BLE.Utils:GetUnitType(unit_path)
        local ud = old_unit and old_unit.unit_data
        local wd = old_unit and old_unit.wire_data 
        local ad = old_unit and old_unit.ai_editor_data
        data = {
            unit_data = {
                unit_id = unit_id or managers.worlddefinition:GetNewUnitID(ud and ud.continent or self._current_continent, t),
                name = unit_path,
                mesh_variation = ud and ud.mesh_variation,
                position = self:GetSpawnPosition(ud),
                rotation = ud and ud.rotation or Rotation(0,0,0),
                continent = ud and ud.continent or self._current_continent,
                material_variation = ud and ud.material_variation,
                disable_shadows = ud and ud.disable_shadows,
                disable_collision = ud and ud.disable_collision,
                hide_on_projection_light = ud and ud.hide_on_projection_light,
                disable_on_ai_graph = ud and ud.disable_on_ai_graph,
                lights = ud and ud.lights,
                projection_light = ud and ud.projection_light,
                projection_lights = ud and ud.projection_lights,
                projection_textures = ud and ud.projection_textures,
                triggers = ud and ud.triggers, 
                editable_gui = ud and ud.editable_gui,
                ladder = ud and ud.ladder, 
                zipline = ud and ud.zipline,
                cubemap = ud and ud.cubemap,
            }
        }
        if t == Idstring("wire") then
            data.wire_data = wd or {
                slack = 0,
                target_pos = data.unit_data.position,
                target_rot = Rotation() 
            }
        elseif t == Idstring("ai") then
            data.ai_editor_data = ad or {
                visibilty_exlude_filter = {},
                visibilty_include_filter = {},
                location_id = "location_unknown",
                suspicion_mul = 1,
                detection_mul = 1                
            }
        end
    end
    local unit = managers.worlddefinition:create_unit(data, t)
    if alive(unit) then
        self:select_unit(unit, add)
        if unit:name() == m.static._nav_surface then
            table.insert(m.static._nav_surfaces, unit)
        end
    else
        BLE:log("Got a nil unit '%s' while attempting to spawn it", tostring(unit_path))
    end    
    return unit
end

function Editor:set_camera(pos, rot)
    if pos then
        self._camera_object:set_position(pos)
        self._camera_pos = pos
    end
    if rot then
        self._camera_object:set_rotation(rot)
        self._camera_rot = rot
    end
end

function Editor:set_enabled(enabled)
    self._enabled = enabled
    if enabled then
        self._menu:Enable()
        managers.hud:set_disabled()
    else
        self._menu:Disable()
        managers.hud:set_enabled()
    end
    self._vp:set_active(enabled)
    if type(managers.enemy) == "table" then
        managers.enemy:set_gfx_lod_enabled(not enabled)
    end
    for _, manager in pairs(m) do
        if enabled then
            if manager.enable then
                manager:enable()
            end        
        else
            if manager.disable then
                manager:disable()
            end
        end
    end
    if Global.check_load_time then
    	BLE.Utils:Notify("Info", string.format("It took %.2f seconds to load your level into the editor", Global.check_load_time))
        Global.check_load_time = nil
    end
end

function Editor:set_unit_positions(pos)
    local reference = self:widget_unit()
    if alive(reference) then
        local old_pos = self:widget_unit():position()
        if not self._using_move_widget and (old_pos ~= pos) then
            self:StorePreviousPosRot()
            self._old_units = self:selected_units()
        end
        BLE.Utils:SetPosition(reference, pos, reference:rotation())
        for _, unit in pairs(m.static._selected_units) do
            if unit ~= reference then
                local ud = unit:unit_data()
                BLE.Utils:SetPosition(unit, pos + ud.local_pos:rotate_with(reference:rotation()), nil, ud) 
            end
        end
    end
end

function Editor:set_unit_rotations(rot)
    local reference = self:widget_unit()
    if alive(reference) then
        local old_rot = self:widget_unit():rotation()
        if not self._using_rotate_widget and (old_rot ~= rot) then
            self:StorePreviousPosRot()
            self._old_units = self:selected_units()
        end
        BLE.Utils:SetPosition(reference, reference:position(), rot)
        for i, unit in pairs(m.static._selected_units) do
            if unit ~= reference then
                local ud = unit:unit_data()
                BLE.Utils:SetPosition(unit, reference:position() + ud.local_pos:rotate_with(rot), rot * ud.local_rot, ud) 
            end
        end
    end
end

function Editor:set_unit_position(unit, pos, rot) 
    local ud = unit:unit_data()
    rot = rot or ud.rotation
    if pos then
        BLE.Utils:SetPosition(unit, pos + ud.local_pos:rotate_with(rot), rot, ud) 
    else
        BLE.Utils:SetPosition(unit, ud.position, rot, ud) 
    end
end

function Editor:load_continents(continents)
    self._continents = {}
    self._current_script = managers.mission._scripts[self._current_script] and self._current_script
    self._current_continent = continents[self._current_continent] and self._current_continent
    if not self._current_script then
        for script, _ in pairs(managers.mission._scripts) do
            self._current_script = self._current_script or script
            break
        end
    end
    for continent, _ in pairs(continents) do
        self._current_continent = self._current_continent or continent
        table.insert(self._continents, continent)
    end
    for _, manager in pairs(m) do
        if manager.loaded_continents then
            manager:loaded_continents(self._continents, self._current_continent)
        end
    end
end

function Editor:set_camera_fov(fov)
    if math.round(self:camera():fov()) ~= fov then
        self._vp:pop_ref_fov()
        self._vp:push_ref_fov(fov)
        self:camera():set_fov(fov)
    end
end

--Short functions
function Editor:set_use_surface_move(value) self._use_surface_move = value end
function Editor:update_snap_rotation(value) self._snap_rotation = tonumber(value) end
function Editor:destroy() self._vp:destroy() end
function Editor:add_element(element, item) m.mission:add_element(element) end
function Editor:Log(...) m.console:Log(...) end
function Editor:Error(...) m.console:Error(...) end

--Return functions
function Editor:local_rot() return true end
function Editor:enabled() return self._enabled end
function Editor:selected_unit() return self:selected_units()[1] end
function Editor:selected_units() return m.static._selected_units end
function Editor:widget_unit() return m.static:widget_unit() or self:selected_unit() end
function Editor:widget_rot() return self:widget_unit():rotation() end
function Editor:is_using_widget() return self._using_move_widget or self._using_rotate_widget end
function Editor:grid_size() return ctrl() and 1 or self._grid_size end
function Editor:camera_rotation() return self._camera_object:rotation() end
function Editor:camera_position() return self._camera_object:position() end
function Editor:snap_rotation() return ctrl() and 1 or self._snap_rotation end
function Editor:get_cursor_look_point(dist) return self._camera_object:screen_to_world(self:cursor_pos() + Vector3(0, 0, dist)) end
function Editor:world_to_screen(pos) return self._camera_object:world_to_screen(pos) end
function Editor:screen_to_world(pos, dist) return self._camera_object:screen_to_world(pos + Vector3(0, 0, dist)) end
function Editor:camera() return self._camera_object end
function Editor:viewport() return self._vp end
function Editor:camera_fov() return self:camera():fov() end
function Editor:set_camera_far_range(range) return self:camera():set_far_range(range) end

function Editor:cam_spawn_pos()
    local cam = managers.viewport:get_current_camera()
    return cam:position() + (cam:rotation():y() * 100)
end

function Editor:_should_draw_body(body)
    if not body:enabled() then
        return false
    end
    if body:has_ray_type(Idstring("editor")) and not body:has_ray_type(Idstring("walk")) and not body:has_ray_type(Idstring("mover")) then
        return false
    end
    if body:has_ray_type(Idstring("widget")) then
        return false
    end
    return true
end

function Editor:cursor_pos()
    local x, y = managers.mouse_pointer._mouse:position()
    return Vector3(x / self._screen_borders.width * 2 - 1, y / self._screen_borders.height * 2 - 1, 0)
end

function Editor:select_unit_by_raycast(slot, clbk)
    local first = true
    local ignore = m.opt:get_value("IgnoreFirstRaycast")
    local distance = m.opt:get_value("RaycastDistance")
    local select_all = m.opt:get_value("SelectAllRaycast")
    local rays = World:raycast_all("ray", self:get_cursor_look_point(0), self:get_cursor_look_point(distance), "ray_type", "body editor walk", "slot_mask", slot)
    local ret_rays = {}
    if #rays > 0 then
        for _, r in pairs(rays) do
            if clbk(r.unit) then
                if not ignore or not first then
                    table.insert(ret_rays, r)
                    if not select_all then
                        return ret_rays
                    end
                else
                    first = false
                end
            end
        end
        return ret_rays
    else
        return false
    end
end

--Update functions
function Editor:paused_update(t, dt) self:update(t, dt) end
function Editor:update(t, dt)
    if BeardLib.Utils.Input:Triggered(self._toggle_trigger) then
        if not self._enabled then
            self._before_state = game_state_machine:current_state_name()
            game_state_machine:change_state_by_name("editor")
        elseif managers.platform._current_presence == "Playing" then
            game_state_machine:change_state_by_name(self._before_state or "ingame_waiting_for_players")
        else
            game_state_machine:change_state_by_name("ingame_waiting_for_players")
        end
    end
    if self:enabled() then
        self._current_pos = self:current_position() or self._current_pos
        if not m.cubemap_creator:creating_cube_map() then
            for _, manager in pairs(m) do
                if manager.update then
                    manager:update(t, dt)
                end
            end

            self:update_camera(t, dt)
            self:update_widgets(t, dt)
            self:draw_marker(t, dt)
            self:draw_grid(t, dt)
            self:draw_ruler(t, dt)
        else
            m.cubemap_creator:update(t, dt)
        end
    end
end

function Editor:current_position()
    local current_pos, current_rot
    local p1 = self:get_cursor_look_point(0)
    local p2, ray

    local unit = self:selected_unit()
    local grid_size = self:grid_size()
    
    if self._use_surface_move or ctrl() then
        p2 = self:get_cursor_look_point(25000)
        local rays = World:raycast_all(p1, p2, nil, managers.slot:get_mask("surface_move"))
        if rays then
            for _, unit_r in pairs(rays) do
                if unit_r.unit ~= unit and unit_r.unit:visible() then
                    ray = unit_r
                    break
                end
            end
        end
        if ray then
            local p = ray.position
            local n = ray.normal
            local x = math.round(p.x / grid_size + n.x) * grid_size
            local y = math.round(p.y / grid_size + n.y) * grid_size
            local z = math.round(p.z / grid_size + n.z) * grid_size
            current_pos = Vector3(x, y, z)

            if alive(unit) then
                local u_rot = unit:rotation()
                local z = n
                local x = (u_rot:x() - z * z:dot(u_rot:x())):normalized()
                local y = z:cross(x)
                local rot = Rotation(x, y, z)
                current_rot = rot * unit:rotation():inverse()
            end
        end
    else
        p2 = self:get_cursor_look_point(100)
        if p1.z - p2.z ~= 0 then
            local t = (p1.z - 0) / (p1.z - p2.z)
            local p = p1 + (p2 - p1) * t
            if t < 1000 and t > -1000 then
                local x = math.round(p.x / grid_size) * grid_size
                local y = math.round(p.y / grid_size) * grid_size
                local z = math.round(p.z / grid_size) * grid_size
                current_pos = Vector3(x, y, z)
            end
        end
    end

    self._current_pos = current_pos or self._current_pos
    return current_pos, current_rot
end

local v0 = Vector3()
function Editor:update_camera(t, dt)
    
    local shft = shift()
    local move = not (self._menu:Focused() or BeardLib.managers.dialog:Menu():Focused())
    if not move or not shft then
        managers.mouse_pointer:_activate()
    end
    local camera_speed = BLE.Options:GetValue("Map/CameraSpeed")
    local move_speed, turn_speed, pitch_min, pitch_max = 1000, 1, -80, 80
    local axis_move = self._con:get_input_axis("freeflight_axis_move")
    local axis_look = self._con:get_input_axis("freeflight_axis_look")
    local btn_move_up = self._con:get_input_float("freeflight_move_up")
    local btn_move_down = self._con:get_input_float("freeflight_move_down")
    local move_dir = self._camera_rot:x() * axis_move.x + self._camera_rot:y() * axis_move.y
    if self._orthographic then
        self._mul = self._mul + (camera_speed * (btn_move_up - btn_move_down))/50
        self:set_orthographic_screen()
    else
        move_dir = move_dir + btn_move_up * Vector3(0, 0, 1) + btn_move_down * Vector3(0, 0, -1)
    end
    local move_delta = move_dir * camera_speed * move_speed * dt
    local pos_new = self._camera_pos + move_delta
    local yaw_new = self._camera_rot:yaw() + axis_look.x * -1 * 5 * turn_speed
    local pitch_new = math.clamp(self._camera_rot:pitch() + axis_look.y * 5 * turn_speed, pitch_min, pitch_max)
    local rot_new = Rotation(yaw_new, pitch_new, 0)
    local keep_active = m.opt and m.opt:get_value("KeepMouseActiveWhileFlying")
    if keep_active then
        if mvector3.not_equal(v0, axis_move) or mvector3.not_equal(v0, axis_look) or btn_move_up ~= 0 or btn_move_down ~= 0 then
            self:mouse_moved(managers.mouse_pointer:world_position())
        end
    elseif shft and move then
        managers.mouse_pointer:_deactivate()
    end
    if move then
        self:set_camera(pos_new, shft and rot_new or self:camera_rotation())
    end
end

function Editor:update_widgets(t, dt)
    if alive(self:widget_unit()) then
        local widget_pos = self:world_to_screen(self:widget_unit():position())
        if widget_pos.z > 50 then
            widget_pos = widget_pos:with_z(0)
            local widget_screen_pos = widget_pos
            widget_pos = self:screen_to_world(widget_pos, 1000)
            local widget_rot = self:widget_rot()
            if self._using_move_widget and self._move_widget:enabled() then
                local result_pos = self._move_widget:calculate(self:widget_unit(), widget_rot, widget_pos, widget_screen_pos)
                if self._last_pos ~= result_pos then 
                    self:set_unit_positions(result_pos)
                    self:update_positions()                    
                end
                self._last_pos = result_pos
            end
            if self._using_rotate_widget and self._rotate_widget:enabled() then
                local result_rot = self._rotate_widget:calculate(self:widget_unit(), widget_rot, widget_pos, widget_screen_pos)
                if self._last_rot ~= result_rot then
                    self:set_unit_rotations(result_rot)
                    self:update_positions()
                end
                self._last_rot = result_rot
            end
            if self._move_widget:enabled() then
                if self._last_pos ~= nil then
                    self:set_unit_positions(self._last_pos)
                    self._last_pos = nil
                end
                BLE.Utils:SetPosition(self._move_widget._widget, widget_pos, widget_rot)
                self._move_widget:update(t, dt)
            end
            if self._rotate_widget:enabled() then
                if self._last_rot ~= nil then
                    self:set_unit_rotations(self._last_rot)
                    self._last_rot = nil
                end               
                BLE.Utils:SetPosition(self._rotate_widget._widget, widget_pos, widget_rot)
                self._rotate_widget:update(t, dt)
            end
        end
    end
end

function Editor:draw_marker(t, dt)
    local pos = self._current_pos
    if not self._use_surface_move and not ctrl() then
        local rays = World:raycast_all(self:get_cursor_look_point(0), self:get_cursor_look_point(10000), nil, self._editor_all)
        for _, ray in pairs(rays) do
            if ray and ray.unit ~= m.world._dummy_spawn_unit then
                pos = ray.position
                break
            end
        end
    end
    self._spawn_position = pos
end

-- TODO make the grid draw like the widgets
function Editor:draw_grid(t, dt)

	local rot = Rotation(0, 0, 0)
	if alive(self:selected_unit()) and self:local_rot() then
		rot = self:selected_unit():rotation()
    end

    if self._using_move_widget and self._move_widget:enabled() and self:widget_unit() then
        for i = -12, 12, 1 do
            local from_x = (self:widget_unit():position() + rot:x() * i * self:grid_size()) - rot:y() * 12 * self:grid_size()
            local to_x = self:widget_unit():position() + rot:x() * i * self:grid_size() + rot:y() * 12 * self:grid_size()

            Application:draw_line(from_x, to_x, 0, 0.5, 0)

            local from_y = (self:widget_unit():position() + rot:y() * i * self:grid_size()) - rot:x() * 12 * self:grid_size()
            local to_y = self:widget_unit():position() + rot:y() * i * self:grid_size() + rot:x() * 12 * self:grid_size()

            Application:draw_line(from_y, to_y, 0, 0.5, 0)
        end
    end
end

function Editor:draw_ruler(t, dt)
	if not self._start_pos then
		return
	end

	local start_pos = self._start_pos
    local end_pos = self._current_pos
    self._end_pos = end_pos

	Application:draw_sphere(start_pos, 10, 1, 1, 1)
	Application:draw_sphere(end_pos, 10, 1, 1, 1)
	Application:draw_line(start_pos, end_pos, 1, 1, 1)
end

function Editor:update_positions()
    for _, manager in pairs(m) do
        if manager.update_positions then
            manager:update_positions()
        end
    end
end

function Editor:set_orthographic_screen()
	local res = Application:screen_resolution()
	self._camera_object:set_orthographic_screen( -(res.x/2)*self._mul, (res.x/2)*self._mul, -(res.y/2)*self._mul, (res.y/2)*self._mul )
end

function Editor:toggle_orthographic(item)
    local camera = self._camera_object
    local use = item:Value()
	if use then
        self._orthographic = true
		self._camera_settings = {}
		self._camera_settings.far_range = camera:far_range()
		self._camera_settings.near_range = camera:near_range()
		self._camera_settings.position = camera:position()
		self._camera_settings.rotation = camera:rotation()
		camera:set_projection_type(Idstring("orthographic"))
		self:set_orthographic_screen()
		camera:set_position(Vector3(0, 0, camera:position().z))
		camera:set_rotation(Rotation(math.DOWN, Vector3(0, 1, 0)))
		camera:set_far_range(75000)
	else
        self._orthographic = false
		camera:set_projection_type(Idstring("perspective"))
		camera:set_far_range(self._camera_settings.far_range)
		camera:set_near_range(self._camera_settings.near_range)
		camera:set_position(self._camera_settings.position)
		camera:set_rotation(self._camera_settings.rotation)
	end
end


--Empty/Unused functions
function Editor:register_message()end
function Editor:set_value_info_pos() end
function Editor:set_value_info() end

function Editor:_set_fixed_resolution(size)
    Application:set_mode(size.x, size.y, false, -1, false, true)
	managers.viewport:set_aspect_ratio2(size.x / size.y)

	if managers.viewport then
		managers.viewport:resolution_changed()
	end

end
