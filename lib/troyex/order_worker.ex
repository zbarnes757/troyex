defmodule Troyex.OrderWorker do
  use GenServer
  require Logger

  defmodule State do
    defstruct open_postion: nil
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

  #############
  # Callbacks #
  #############

  def init(_) do
    {:ok, %State{}}
  end

  def handle_cast({:buy, %{"asks" => {_min, max}, "instrument" => instrument, "closeoutAsk" => closeout}}, %State{open_postion: nil} = state) do
    case send_order(:buy, instrument, 10_000, max, closeout) do
      {:ok, %HTTPoison.Response{status_code: 201}} ->
        Logger.debug "Successfully posted order"
        {:noreply, %{state | open_postion: :buy}}
      _ ->
        Logger.error "failed to post order"
        {:noreply, state}
    end
  end

  def handle_cast({:buy, _price}, state) do
    Logger.debug "Already in open position. Going to do nothing"
    {:noreply, state}
  end

  def handle_cast({:sell, %{"bids" => {min, _max}, "instrument" => instrument, "closeoutBid" => closeout}}, %State{open_postion: nil} = state) do
    case send_order(:sell, instrument, -10_000, min, closeout) do
      {:ok, %HTTPoison.Response{status_code: 201}} ->
        Logger.debug "Successfully posted order"
        {:noreply, %{state | open_postion: :sell}}
      {:ok, %HTTPoison.Response{status_code: _, body: body}} ->
        {:ok, message} = Poison.decode(body)
        Logger.error "Failed to post order. #{inspect message}"
        {:noreply, %{state | open_postion: :sell}}
      a ->
        Logger.error "failed to post order. #{inspect a}"
        {:noreply, state}
    end
  end

  def handle_cast({:sell, _price}, state) do
    Logger.debug "Already in open position. Going to do nothing"
    {:noreply, state}
  end

  #####################
  # Private Functions #
  #####################

  defp send_order(:buy, instrument, units, price, closeout) do
    body = %{
      order: %{
        type: "MARKET",
        instrument: instrument,
        units: units,
        takeProfitOnFill: %{
          price: "#{Float.round(closeout + 0.00007, 5)}"
        },
        stopLossOnFill: %{
          price: "#{Float.round(price - 0.00005, 5)}"
        }
      }
    }

    headers = [
      {"Authorization", "Bearer #{oanda_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.debug "Sending order for #{inspect body}"
    HTTPoison.post("https://api-fxpractice.oanda.com/v3/accounts/#{account_id()}/orders", Poison.encode!(body), headers)
  end
  defp send_order(:sell, instrument, units, price, closeout) do
    body = %{
      order: %{
        type: "MARKET",
        instrument: instrument,
        units: units,
        takeProfitOnFill: %{
          price: "#{Float.round(closeout - 0.00007, 5)}"
        },
        stopLossOnFill: %{
          price: "#{Float.round(price + 0.00005, 5)}"
        }
      }
    }

    headers = [
      {"Authorization", "Bearer #{oanda_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.debug "Sending order for #{inspect body}"
    HTTPoison.post("https://api-fxpractice.oanda.com/v3/accounts/#{account_id()}/orders", Poison.encode!(body), headers)
  end

  defp oanda_token do
    Application.get_env(:troyex, :oanda_key)
  end

  defp account_id do
    Application.get_env(:troyex, :account_id)
  end

end