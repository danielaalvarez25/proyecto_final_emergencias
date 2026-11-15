defmodule Resumen do
  def generar do
    with {:ok, recursos} <- Recursos.listar(),
         {:ok, necesidades} <- Necesidades.listar(),
         {:ok, albergues} <- Albergues.listar(),
         {:ok, usuarios} <- Usuarios.listar(),
         {:ok, zonas} <- Zonas.listar(),
         {:ok, personas} <- Personas.buscar(),
         {:ok, mascotas} <- Mascotas.listar() do
      mensajes = mensajes_de_personas(personas)

      {:ok,
       %{
         recursos: recursos,
         necesidades_pendientes:
           Enum.filter(necesidades, &(&1.estado == :pendiente)),
         albergues: albergues,
         usuarios_conectados:
           usuarios
           |> Enum.filter(& &1.conectado)
           |> Enum.map(& &1.username),
         zonas: zonas,
         personas_localizadas:
           Enum.filter(personas, fn persona ->
             persona.estado in [:localizada, :en_albergue, :reunificada]
           end),
         mensajes: mensajes,
         mensajes_pendientes:
           Enum.filter(mensajes, &(&1.estado == :pendiente)),
         mascotas: mascotas
       }}
    end
  end

  defp mensajes_de_personas(personas) do
    Enum.flat_map(personas, fn persona ->
      case Personas.listar_mensajes(persona.documento) do
        {:ok, mensajes} -> mensajes
        {:error, _razon} -> []
      end
    end)
  end
end
