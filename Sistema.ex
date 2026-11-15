defmodule Sistema do
  use Supervisor

  #Raíz del árbol de supervisión del sistema de emergencias.

  #Es un Supervisor con estrategia :one_for_one: si uno de sus procesos
  #falla, solo se reinicia ese proceso y los demás siguen funcionando.

  def iniciar do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    hijos = [
      Recursos,
      Necesidades,
      Albergues,
      Despacho,
      Usuarios,
      Zonas,
      Personas,
      Mascotas
    ]

    Supervisor.init(hijos, strategy: :one_for_one)
  end
end
