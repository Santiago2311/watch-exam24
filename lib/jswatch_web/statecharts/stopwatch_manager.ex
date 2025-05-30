defmodule JswatchWeb.StopwatchManager do
  use GenServer

  def init(ui) do
    :gproc.reg({:p, :l, :ui_event})
    count = ~T[00:00:00.000]
    GenServer.cast(ui, {:set_time_display, count |> Time.to_string() |> String.slice(3, 8)})

    {:ok,
     %{
       ui_pid: ui,
       count: count,
       mode: :Time,
       watching_mode: :Working,
       stopwatch_state: :Idle,
       timer: nil
     }}
  end

  # stop-clock transition (bottom-left cuando está en Working y mode SWatch)
  def handle_info(
        :"bottom-left-pressed",
        %{ui_pid: ui, mode: :SWatch, watching_mode: :Working} = state
      ) do
    count = ~T[00:00:00.000]
    GenServer.cast(ui, {:set_time_display, count |> Time.to_string() |> String.slice(3, 8)})
    {:noreply, %{state | count: count}}
  end

  # top-left transition para cambiar entre modos
  def handle_info(
        :"top-left-pressed",
        %{ui_pid: ui, mode: mode, count: count, watching_mode: :Working} = state
      ) do
    new_mode =
      if mode == :SWatch do
        :Time
      else
        GenServer.cast(ui, {:set_time_display, count |> Time.to_string() |> String.slice(3, 8)})
        :SWatch
      end

    {:noreply, %{state | mode: new_mode}}
  end

  # resume-clock transition (bottom-right desde Idle a Counting)
  def handle_info(
        :"bottom-right-pressed",
        %{ui_pid: ui, mode: :SWatch, stopwatch_state: :Idle, count: count} = state
      ) do
    # Verificar si se está editando la hora
    case :gproc.lookup_values({:p, :l, :edit_mode}) do
      [] ->
        count = Time.add(count, 10, :millisecond)
        IO.inspect("Iniciando cronómetro")
        timer = Process.send_after(self(), :counting_tick, 10)
        GenServer.cast(ui, {:set_time_display, count |> Time.to_string() |> String.slice(3, 8)})
        :gproc.reg({:p, :l, :stopwatch_running})
        {:noreply, %{state | stopwatch_state: :Counting, count: count, timer: timer}}

      _ ->
        IO.inspect("No se puede iniciar cronómetro mientras se edita la hora")
        {:noreply, state}
    end
  end

  # stop-clock transition (bottom-right desde Counting a Idle)
  def handle_info(
        :"bottom-right-pressed",
        %{stopwatch_state: :Counting, mode: :SWatch, timer: timer} = state
      ) do
    if timer != nil do
      Process.cancel_timer(timer)
    end

    IO.inspect("Deteniendo cronómetro")
    :gproc.unreg({:p, :l, :stopwatch_running})
    {:noreply, %{state | stopwatch_state: :Idle, timer: nil}}
  end

  # after 10ms internal transition en estado Counting
  def handle_info(
        :counting_tick,
        %{ui_pid: ui, stopwatch_state: :Counting, mode: mode, count: count} = state
      ) do
    count = Time.add(count, 10, :millisecond)
    timer = Process.send_after(self(), :counting_tick, 10)

    if mode == :SWatch do
      GenServer.cast(ui, {:set_time_display, count |> Time.to_string() |> String.slice(3, 8)})
    end

    {:noreply, %{state | stopwatch_state: :Counting, count: count, timer: timer}}
  end

  def handle_info(_event, state) do
    {:noreply, state}
  end
end
