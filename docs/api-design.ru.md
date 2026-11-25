# Проект API StrataQL для Elixir

Статус — API реализован в форке. Сегодня доступны именованный процесс соединения, query/3, query_raw/3, query!/3, RecordId и явные begin/1, commit/1, cancel/1. Ниже описаны три дополнения в модуле SurrealDB. Пакет сохраняет имя strata_ql. Все существующие формы ответов сохраняются.

## От требования к функции

Требование службы доставки — диспетчер получает открытые заказы своего склада в порядке создания. При одинаковом времени порядок определяет id. Пустая очередь является успешным результатом. Идентификатор склада поступает от вызывающего кода как SurrealDB.RecordId. Приложение проверяет, что у диспетчера есть доступ к складу.

```elixir
defmodule Dispatch.Orders do
  alias SurrealDB.RecordId

  @open_orders """
  SELECT id, created_at FROM orders
  WHERE warehouse = $warehouse AND state = 'open'
  ORDER BY created_at ASC, id ASC
  """

  @spec open_orders(SurrealDB.data_handle(), RecordId.t()) ::
          {:ok, [map()]} | {:error, SurrealDB.Error.t()}
  def open_orders(db, %RecordId{} = warehouse) do
    SurrealDB.all(db, @open_orders, %{warehouse: warehouse})
  end
end
```

Доменный модуль владеет текстом запроса, именами параметров и публичным типом результата. Значения передаются отдельно от SurrealQL. Ключи записей остаются строками. Когда приложению нужен доменный struct, оно явно преобразует поля на этой границе.

В supervision tree приложение регистрирует SurrealDB.Connection под именем Dispatch.DB, как в примере README. Обработчик вызывает Dispatch.Orders.open_orders(Dispatch.DB, warehouse). В интеграционном тесте первым аргументом служит pid тестового соединения, внутри транзакции — tx. Для этого пути достаточно обычного модуля и функций Elixir.

## Контракты чтения

Обе новые функции принимают (db, surql, vars), vars по умолчанию равен %{}. Сначала SDK вызывает существующий query/3. Ошибка запроса передаётся без изменений. Для успешного ответа применяется следующий контракт.

| Ответ query/3 | all/3 | fetch_one/3 |
| --- | --- | --- |
| {:ok, [[]]} | {:ok, []} | :error |
| {:ok, [[row]]} | {:ok, [row]} | {:ok, row} |
| {:ok, [[a, b]]} | {:ok, [a, b]} | {:error, %SurrealDB.Error{kind: :cardinality}} |
| Несколько результатов statements, скаляр или отсутствие statements | ошибка :result_shape | ошибка :result_shape |

row может быть любым декодированным значением, в том числе из SELECT VALUE. SDK проверяет только внешний контейнер и число элементов. :error выражает отсутствие значения по соглашению Map.fetch/2. Сбой базы всегда возвращает пару {:error, error}. :result_shape и :cardinality расширяют тип SurrealDB.Error.kind(). Поле details содержит ожидаемую форму и фактическое количество, когда оно известно. Для обнаружения дубликата в запросе поиска по бизнес-ключу достаточно LIMIT 2. LIMIT 1 скрыл бы нарушение требования уникальности.

## Атомарное изменение

Требование — создать заказ и событие в одной транзакции. Доменная функция возвращает созданный заказ только после подтверждения commit.

```elixir
SurrealDB.transaction(db, fn tx ->
  with {:ok, [order]} <- SurrealDB.create(tx, "orders", attrs),
       {:ok, _} <- SurrealDB.create(tx, "events", %{order: order["id"], kind: "placed"}) do
    {:ok, order}
  end
end)
```

transaction/2 на WebSocket вызывает begin один раз и передаёт tx в callback. {:ok, value} запрашивает commit. {:error, reason} запрашивает cancel и при его подтверждении возвращает исходную пару, включая доменные причины вроде :out_of_stock. Другой результат callback считается ошибкой контракта и вызывает ArgumentError после попытки cancel. Для исключения, throw или перехватываемого exit SDK пытается отменить транзакцию и повторно передаёт исходный сигнал со стеком. Принудительное завершение процесса исключает гарантию выполнения cleanup.

При сбое cancel после доменной ошибки вызывающий получает ошибку с обеими причинами в details. Потеря ответа на commit возвращает ошибку :transaction_unknown с причиной в details. SDK не повторяет callback или запись автоматически. Передача tx в transaction/2 и HTTP-соединение возвращают :unsupported до запуска callback. Обычные вызовы через db во время callback остаются вне транзакции.

## Проверка требований

Пример приёмочного теста приложения. Фикстура создаёт два открытых заказа одного склада в обратном порядке времени, закрытый заказ того же склада и открытый заказ другого склада. Она возвращает id первых двух в ожидаемом порядке.

```elixir
test "очередь содержит только открытые заказы выбранного склада", %{db: db} do
  %{warehouse: warehouse, expected_ids: ids} = seed_dispatch_queue!(db)
  assert {:ok, rows} = Dispatch.Orders.open_orders(db, warehouse)
  assert Enum.map(rows, &Map.fetch!(&1, "id")) == ids
end
```

