#!/bin/bash

# TeslaMate PostgreSQL 升级脚本
# 用于简化 TeslaMate 的数据库备份、升级和恢复操作
# 适合小白用户，提供中文菜单界面

# 颜色定义，便于输出美化
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查必要工具是否安装
check_environment() {
    echo -e "${YELLOW}正在检查环境...${NC}"
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误：未安装 Docker！请先安装 Docker。${NC}"
        exit 1
    fi
    if ! command -v docker compose &> /dev/null; then
        echo -e "${RED}错误：未安装 Docker Compose！请先安装 Docker Compose v2。${NC}"
        exit 1
    fi
    echo -e "${GREEN}环境检查通过！${NC}"
}

# 获取用户输入的 docker-compose.yml 路径
get_compose_path() {
    read -p "请输入 docker-compose.yml 文件所在目录（默认：~/docker-teslamate）： " COMPOSE_DIR
    COMPOSE_DIR=${COMPOSE_DIR:-~/docker-teslamate}
    if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
        echo -e "${RED}错误：$COMPOSE_DIR/docker-compose.yml 文件不存在！${NC}"
        exit 1
    fi
    echo -e "${GREEN}找到 docker-compose.yml：$COMPOSE_DIR/docker-compose.yml${NC}"
}

# 备份数据库
backup_database() {
    echo -e "${YELLOW}开始备份 TeslaMate 数据库...${NC}"
    read -p "请输入备份文件保存路径（默认：~/teslamate_backup.sql）： " BACKUP_FILE
    BACKUP_FILE=${BACKUP_FILE:-~/teslamate_backup.sql}
    echo -e "${YELLOW}将备份数据库到：$BACKUP_FILE${NC}"
    
    # 停止 TeslaMate 容器（避免数据写入）
    echo -e "${YELLOW}正在停止 TeslaMate 容器...${NC}"
    cd "$COMPOSE_DIR" || exit 1
    docker compose down
    
    # 执行备份
    echo -e "${YELLOW}正在执行备份...${NC}"
    if docker compose exec database pg_dump -U teslamate teslamate > "$BACKUP_FILE"; then
        echo -e "${GREEN}备份成功！备份文件：$BACKUP_FILE${NC}"
    else
        echo -e "${RED}备份失败！请检查数据库配置或权限。${NC}"
        exit 1
    fi
}

# 升级 PostgreSQL
upgrade_postgres() {
    echo -e "${YELLOW}开始升级 PostgreSQL...${NC}"
    read -p "请输入目标 PostgreSQL 版本（默认：17，例如 16 或 17）： " PG_VERSION
    PG_VERSION=${PG_VERSION:-17}
    echo -e "${YELLOW}将升级到 PostgreSQL 版本：$PG_VERSION${NC}"
    
    # 确认备份
    read -p "请确认已备份数据库（输入备份文件路径或按 Enter 跳过）： " BACKUP_FILE
    if [ -n "$BACKUP_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}错误：备份文件 $BACKUP_FILE 不存在！${NC}"
        exit 1
    fi
    
    # 停止所有容器
    echo -e "${YELLOW}正在停止所有 TeslaMate 容器...${NC}"
    cd "$COMPOSE_DIR" || exit 1
    docker compose down
    
    # 删除数据库卷
    echo -e "${RED}警告：将删除现有数据库卷，所有数据将丢失！确保已备份。${NC}"
    read -p "确认删除数据库卷？（输入 y 确认）： " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo -e "${YELLOW}已取消操作。${NC}"
        exit 0
    fi
    docker volume rm "$(basename "$PWD")_teslamate-db" || {
        echo -e "${RED}删除数据库卷失败，可能卷名不正确。请检查卷名（docker volume ls）。${NC}"
        exit 1
    }
    
    # 更新 docker-compose.yml 中的 PostgreSQL 版本
    echo -e "${YELLOW}正在更新 docker-compose.yml 中的 PostgreSQL 版本...${NC}"
    sed -i "s|image: postgres:.*|image: postgres:$PG_VERSION|g" docker-compose.yml
    if grep -q "image: postgres:$PG_VERSION" docker-compose.yml; then
        echo -e "${GREEN}成功更新 PostgreSQL 版本到 $PG_VERSION！${NC}"
    else
        echo -e "${RED}更新 docker-compose.yml 失败！请手动检查文件。${NC}"
        exit 1
    fi
    
    # 启动容器
    echo -e "${YELLOW}正在启动 TeslaMate 容器...${NC}"
    if docker compose up -d; then
        echo -e "${GREEN}容器启动成功！${NC}"
    else
        echo -e "${RED}容器启动失败！请检查日志（docker compose logs）。${NC}"
        exit 1
    fi
}

# 恢复数据库
restore_database() {
    echo -e "${YELLOW}开始恢复 TeslaMate 数据库...${NC}"
    read -p "请输入备份文件路径： " BACKUP_FILE
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}错误：备份文件 $BACKUP_FILE 不存在！${NC}"
        exit 1
    fi
    
    # 停止容器
    echo -e "${YELLOW}正在停止 TeslaMate 容器...${NC}"
    cd "$COMPOSE_DIR" || exit 1
    docker compose down
    
    # 恢复数据库
    echo -e "${YELLOW}正在恢复数据库...${NC}"
    if cat "$BACKUP_FILE" | docker compose exec -T database psql -U teslamate -d teslamate; then
        echo -e "${GREEN}数据库恢复成功！${NC}"
    else
        echo -e "${RED}数据库恢复失败！请检查备份文件或数据库配置。${NC}"
        exit 1
    fi
    
    # 启动容器
    echo -e "${YELLOW}正在启动 TeslaMate 容器...${NC}"
    docker compose up -d
}

# 检查配置
check_config() {
    echo -e "${YELLOW}正在检查 TeslaMate 配置...${NC}"
    cd "$COMPOSE_DIR" || exit 1
    if docker compose config; then
        echo -e "${GREEN}docker-compose.yml 配置有效！${NC}"
    else
        echo -e "${RED}docker-compose.yml 配置有问题！请检查文件内容。${NC}"
        exit 1
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}===== TeslaMate PostgreSQL 升级助手 =====${NC}"
    echo "1. 备份 TeslaMate 数据库"
    echo "2. 升级 PostgreSQL 版本"
    echo "3. 恢复备份数据库"
    echo "4. 检查环境和配置"
    echo "5. 退出"
    echo -e "${YELLOW}请输入选项（1-5）：${NC}"
}

# 主程序
main() {
    check_environment
    get_compose_path
    while true; do
        show_menu
        read CHOICE
        case $CHOICE in
            1)
                backup_database
                echo -e "${YELLOW}按 Enter 返回菜单...${NC}"
                read
                ;;
            2)
                upgrade_postgres
                echo -e "${YELLOW}按 Enter 返回菜单...${NC}"
                read
                ;;
            3)
                restore_database
                echo -e "${YELLOW}按 Enter 返回菜单...${NC}"
                read
                ;;
            4)
                check_config
                echo -e "${YELLOW}按 Enter 返回菜单...${NC}"
                read
                ;;
            5)
                echo -e "${GREEN}退出脚本，谢谢使用！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请输入 1-5！${NC}"
                echo -e "${YELLOW}按 Enter 继续...${NC}"
                read
                ;;
        esac
    done
}

# 启动脚本
main
