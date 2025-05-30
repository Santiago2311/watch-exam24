defmodule JswatchWeb.ClockManager do
  use GenServer

  def init(ui) do
    :gproc.reg({:p, :l, :ui_event})
    {_, now} = :calendar.local_time()
    current_time = Time.from_erl!(now)
    alarm = Time.add(Time.from_erl!(now), 10)

    Process.send_after(self(), :working_working, 1000)

    {:ok,
     %{
       ui_pid: ui,
       time: current_time,
       alarm: alarm,
       watching_mode: :Working,
       mode: :Time,
       last_click: nil,
       show: false,
       count: 0,
       edit_time: nil,
       selection: :hour,
       button_pressed: false,
       press_timer: nil
     }}
  end

  # after 1s / time += 1s transition en estado Working
  def handle_info(
        :working_working,
        %{ui_pid: ui, time: time, watching_mode: :Working, mode: mode, alarm: alarm} = state
      ) do
    Process.send_after(self(), :working_working, 1000)
    time = Time.add(time, 1)

    if mode == :Time do
      GenServer.cast(ui, {:set_time_display, Time.truncate(time, :second) |> Time.to_string()})
    end

    if time == alarm do
      :gproc.send({:p, :l, :ui_event}, :start_alarm)
    end

    {:noreply, %{state | time: time}}
  end

  # bottom-right pressed transition (Working -> Waiting)
  def handle_info(
        :"bottom-right-pressed",
        %{watching_mode: :Working, button_pressed: false} = state
      ) do
    now = System.monotonic_time(:millisecond)
    Process.send_after(self(), {:check_press_duration, now}, 250)
    {:noreply, %{state | button_pressed: true, press_timer: now}}
  end

  def handle_info(:"bottom-right-released", state) do
    {:noreply, %{state | button_pressed: false, press_timer: nil}}
  end

  # after 250 ms transition (Waiting -> Editing)
  def handle_info(
        {:check_press_duration, press_start},
        %{
          button_pressed: true,
          press_timer: press_start,
          watching_mode: :Working,
          time: time,
          ui_pid: ui
        } =
          state
      ) do
    case :gproc.lookup_values({:p, :l, :stopwatch_running}) do
      [] ->
        :gproc.reg({:p, :l, :edit_mode})
        IO.inspect("Entrando a modo edición")
        GenServer.cast(ui, {:set_time_display, "EDITING"})
        Process.send_after(self(), :editing_blink, 250)

        {:noreply,
         %{
           state
           | # st -> watching_mode
             watching_mode: :Editing,
             selection: :hour,
             show: true,
             count: 0,
             edit_time: time,
             last_click: nil
         }}

      _ ->
        IO.inspect("No se puede editar mientras el cronómetro está activo")
        {:noreply, state}
    end
  end

  def handle_info({:check_press_duration, _}, state), do: {:noreply, state}

  # after 250 ms blink transition en estado Editing
  def handle_info(
        :editing_blink,
        %{
          watching_mode: :Editing,
          show: show,
          ui_pid: ui,
          edit_time: edit_time,
          selection: selection,
          count: count
        } = state
      ) do
    new_show = !show
    new_count = if new_show, do: count + 1, else: count

    if new_count == 20 do
      send(self(), :exit_editing)
      {:noreply, state}
    else
      {h, m, s} = {edit_time.hour, edit_time.minute, edit_time.second}

      display =
        case selection do
          :hour -> "#{if(new_show, do: pad(h), else: "  ")}:#{pad(m)}:#{pad(s)}"
          :minute -> "#{pad(h)}:#{if(new_show, do: pad(m), else: "  ")}:#{pad(s)}"
          :second -> "#{pad(h)}:#{pad(m)}:#{if(new_show, do: pad(s), else: "  ")}"
        end

      GenServer.cast(ui, {:set_time_display, display})
      Process.send_after(self(), :editing_blink, 250)

      {:noreply, %{state | show: new_show, count: new_count}}
    end
  end

  # bottom-right transition para cambiar selección en modo Editing
  def handle_info(
        :"bottom-right-pressed",
        %{watching_mode: :Editing, selection: selection} = state
      ) do
    new_selection =
      case selection do
        :hour -> :minute
        :minute -> :second
        :second -> :hour
      end

    {:noreply, %{state | selection: new_selection, count: 0}}
  end

  # bottom-left transition para incrementar tiempo en modo Editing
  def handle_info(
        :"bottom-left-pressed",
        %{watching_mode: :Editing, edit_time: edit_time, selection: selection, ui_pid: ui} = state
      ) do
    new_edit_time = increment_time(edit_time, selection)
    GenServer.cast(ui, {:set_time_display, Time.to_string(new_edit_time)})
    {:noreply, %{state | edit_time: new_edit_time, count: 0}}
  end

  # [count == 20] / raise(resume-clock) transition (Editing -> Working)
  def handle_info(
        :exit_editing,
        %{watching_mode: :Editing, edit_time: edit_time, ui_pid: ui} = state
      ) do
    GenServer.cast(ui, {:set_time_display, Time.to_string(edit_time)})
    Process.send_after(self(), :working_working, 1000)
    :gproc.unreg({:p, :l, :edit_mode})

    {:noreply,
     %{
       state
       | # st -> watching_mode
         watching_mode: :Working,
         time: edit_time,
         edit_time: nil,
         selection: nil,
         show: false,
         count: 0
     }}
  end

  def handle_info(_event, state), do: {:noreply, state}

  defp increment_time(time, :hour), do: %{time | hour: rem(time.hour + 1, 24)}
  defp increment_time(time, :minute), do: %{time | minute: rem(time.minute + 1, 60)}
  defp increment_time(time, :second), do: %{time | second: rem(time.second + 1, 60)}

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
