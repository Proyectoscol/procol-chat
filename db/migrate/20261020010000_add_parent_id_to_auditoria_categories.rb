class AddParentIdToAuditoriaCategories < ActiveRecord::Migration[7.2]
  def change
    # :nullify (no :cascade) a proposito: borrar una categoria padre
    # ("Competencia") no debe borrar sus subcategorias ("Kia", "Toyota") --
    # solo las desagrupa a nivel superior, igual que borrar una carpeta no
    # tendria que borrar los archivos que agrupaba.
    add_reference :auditoria_categories, :parent, null: true, index: true,
                                                  foreign_key: { to_table: :auditoria_categories, on_delete: :nullify }
  end
end
