from src import create_app

# Создаем экземпляр приложения
app = create_app()

if __name__ == '__main__':
    # Запускаем сервер в режиме отладки (debug=True)
    # Это позволит серверу автоматически перезагружаться при изменении кода
    app.run(debug=True, port=5000)