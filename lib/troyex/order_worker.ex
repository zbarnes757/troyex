defmodule Troyex.OrderWorker do
  use GenServer
  require Logger

  @oanda_api_domain "https://api-fxpractice.oanda.com"

  defmodule State do
    defstruct open_postion: false
  end

  ##########
  # Client #
  ##########

  def start_link() do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def buy(current_price) do
    GenServer.cast(__MODULE__, {:buy, current_price})
  end

  def sell(current_price) do
    GenServer.cast(__MODULE__, {:sell, current_price})
  end

  def update_positions do
    GenServer.cast(__MODULE__, :update_postions)
  end

  #############
  # Callbacks #
  #############

  def init(_) do
    {:ok, %State{}}
  end

  def handle_cast(
    {:buy, %{"asks" => {_min, price}, "instrument" => instrument, "closeoutAsk" => closeout}},
    %State{open_postion: false} = state
  ) do
    order = %{
      order: %{
        type: "MARKET",
        instrument: instrument,
        units: 10_000,
        takeProfitOnFill: %{
          price: "#{Float.round(closeout + 0.00007, 5)}"
        },
        stopLossOnFill: %{
          price: "#{Float.round(price - 0.00005, 5)}"
        }
      }
    }

    order
    |> send_order()
    |> handle_resp(state)
  end

  def handle_cast({:buy, _price}, state) do
    Logger.debug "Already in open position. Going to do nothing"
    {:noreply, state}
  end

  def handle_cast(
    {:sell, %{"bids" => {price, _max}, "instrument" => instrument, "closeoutBid" => closeout}},
    %State{open_postion: false} = state
  ) do
    order = %{
      order: %{
        type: "MARKET",
        instrument: instrument,
        units: -10_000,
        takeProfitOnFill: %{
          price: "#{Float.round(closeout - 0.00007, 5)}"
        },
        stopLossOnFill: %{
          price: "#{Float.round(price + 0.00005, 5)}"
        }
      }
    }

    order
    |> send_order()
    |> handle_resp(state)
  end

  def handle_cast({:sell, _price}, state) do
    Logger.debug "Already in open position. Going to do nothing"
    {:noreply, state}
  end

  def handle_cast(:update_positions, state) do
    {:noreply, %{state | open_postion: false}}
  end

  #####################
  # Private Functions #
  #####################

  defp send_order(body) do
    Logger.debug "Sending order for #{inspect body}"
    HTTPoison.post("#{@oanda_api_domain}/v3/accounts/#{account_id()}/orders", Poison.encode!(body), headers())
  end

  defp handle_resp({:ok, %HTTPoison.Response{status_code: 201}}, state) do
    Logger.debug "Successfully posted order"

    Troyex.PositionWorker.monitor_positions()

    {:noreply, %{state | open_postion: true}}
  end

  defp handle_resp({:ok, %HTTPoison.Response{status_code: _, body: body}}, state) do
    {:ok, message} = Poison.decode(body)

    Logger.error "Failed to make call. #{inspect message}"

    {:noreply, state}
  end

  defp handle_resp(a, state) do
    Logger.error "Failed to make call. #{inspect a}"

    {:noreply, state}
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