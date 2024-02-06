#!/bin/bash

# Задайте начальную директорию для поиска .h файлов
SOURCE_DIR="."

# Директория для создания символических ссылок
INCLUDE_DIR="${SOURCE_DIR}/include"

# Создать директорию include, если она не существует
mkdir -p "$INCLUDE_DIR"

# Функция для создания символических ссылок
create_symlinks() {
    local src_dir=$1
    local include_dir=$2

    # Найти все .h файлы в src_dir и поддиректориях
    find "$src_dir" -type f -name "*.h" | while read -r header_file; do
        # Получить базовое имя файла для создания ссылки
        local base_name=$(basename "$header_file")

        # Создать символическую ссылку в include_dir
        ln -s "$header_file" "$include_dir/$base_name" 2>/dev/null || echo "Symlink for $base_name already exists."
    done
}

# Вызов функции с заданными параметрами
create_symlinks "$SOURCE_DIR" "$INCLUDE_DIR"

echo "Symlinks for header files are created in $INCLUDE_DIR"
