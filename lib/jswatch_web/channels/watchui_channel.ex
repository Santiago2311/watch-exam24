defmodule JswatchWeb.WatchUIChannel do
  use Phoenix.Channel

  def join("watch:ui", _message, socket) do
    GenServer.start_link(JswatchWeb.ClockManager, self())
    GenServer.start_link(JswatchWeb.IndigloManager, self())
    GenServer.start_link(JswatchWeb.StopwatchManager, self())
    {:ok, socket}
  end

  def handle_in(event, _payload, socket) do
    IO.inspect(event)
    :gproc.send({:p, :l, :ui_event}, String.to_atom(event))
    {:noreply, socket}
  end

  def handle_cast({:set_time_display, str}, socket) do
    push(socket, "setTimeDisplay", %{time: str})
    {:noreply, socket}
  end

  def handle_cast(:set_indiglo, socket) do
    push(socket, "setIndiglo", %{})
    {:noreply, socket}
  end

  def handle_cast(:unset_indiglo, socket) do
    push(socket, "unsetIndiglo", %{})
    {:noreply, socket}
  end

  def handle_cast(:update_alarm, socket) do
    push(socket, "updateAlarm", %{})
    {:noreply, socket}
  end
end
