defmodule Troyex.PositionWorker do
  use GenServer
  require Logger

  @check_open_postions_interval 1_000
  @oanda_api_domain "https://api-fxpractice.oanda.com"

  ##########
  # Client #
  ##########

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def monitor_positions do
    GenServer.cast(__MODULE__, :start_monitoring)
  end

  #############
  # Callbacks #
  #############

  def init(_) do
    {:ok, []}
  end

  def handle_cast(:start_monitoring, state) do
    Process.send_after(self(), :check_open_position, @check_open_postions_interval)

    {:noreply, state}
  end

  def handle_info(:check_open_position, state) do
    Logger.debug "Checking open position to see if closed yet."

    check_open_positions() |> handle_resp()

    {:noreply, state}
  end

  #####################
  # Private Functions #
  #####################

  defp check_open_positions do
    HTTPoison.get("#{@oanda_api_domain}/v3/accounts/#{account_id()}/openPositions", headers())
  end

  defp handle_resp({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    body
    |> Poison.decode!()
    |> Map.get("positions")
    |> Enum.empty?()
    |> case do
      true ->
        Logger.debug "No positions open. Updating state."

        Troyex.OrderWorker.update_positions()
      false ->
        Logger.debug "Position still open."

        Process.send_after(self(), :check_open_position, @check_open_postions_interval)
    end
  end

  defp handle_resp({:ok, %HTTPoison.Response{status_code: _, body: body}}) do
    {:ok, message} = Poison.decode(body)

    Logger.error "Failed to make call. #{inspect message}"
  end

  defp handle_resp(a) do
    Logger.error "Failed to make call. #{inspect a}"
  end

  defp oanda_token do
    Application.get_env(:troyex, :oanda_key)
  end

  defp account_id do
    Application.get_env(:troyex, :account_id)
  end

  defp headers do
    [
      {"Authorization", "Bearer #{oanda_token()}"},
      {"Content-Type", "application/json"}
    ]
  end
end