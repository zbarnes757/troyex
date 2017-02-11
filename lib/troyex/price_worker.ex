defmodule Troyex.PriceWorker do
  use GenServer
  require Logger

  ##########
  # Client #
  ##########

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def send_price(price_chunk) do
    GenServer.cast(__MODULE__, {:send_price, price_chunk})
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  #############
  # Callbacks #
  #############

  def init(_) do
    {:ok, []}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:send_price, price_chunk}, state) when length(state) > 4 do
    Logger.debug "Received price info for #{price_chunk["instrument"]}"
    new_state = state ++ [price_chunk]

    new_state
    |> Enum.take(-4)
    |> check_for_trend()

    {:noreply, new_state}
  end

  def handle_cast({:send_price, price_chunk}, state) do
    Logger.debug "Received price info for #{price_chunk["instrument"]}"
    {:noreply, state ++ [price_chunk]}
  end

  #####################
  # Private Functions #
  #####################

  defp check_for_trend(prices) do
    [first_bid, second_bid, third_bid, fourth_bid] =  Enum.map(prices, fn(%{"bids" => {min, _max}}) -> min end)
    [first_ask, second_ask, third_ask, fourth_ask] =  Enum.map(prices, fn(%{"asks" => {_min, max}}) -> max end)

    cond do
      # Prices are increasing, make a long order
      first_ask < second_ask
      && second_ask < third_ask
      && third_ask < fourth_ask ->
        prices
        |> List.last()
        |> Troyex.OrderWorker.buy()

      # prices are decreasing, make a short order
      first_bid > second_bid
      && second_bid > third_bid
      && third_bid > fourth_bid ->
        prices
        |> List.last()
        |> Troyex.OrderWorker.sell()

      # no pattern so no op
      true -> nil
    end
  end

end