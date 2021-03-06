/*
    Plugin is based on WalkGuard (https://forums.alliedmods.net/showthread.php?t=55245).
    Thanks a mogel (https://forums.alliedmods.net/member.php?u=24745) for base (WalkGuard v1.3.2).
*/

#include <amxmodx>
#include <engine>

#if AMXX_VERSION_NUM < 183
    #include <colorchat>
#endif

#if !defined client_disconnected
    #define client_disconnected client_disconnect
#endif

new const PLUGIN_NAME[]    = "Walls Creator";
new const PLUGIN_VERSION[] = "1.0";
new const PLUGIN_AUTHOR[]  = "d3m37r4";

const ACCESS_FLAG = ADMIN_LEVEL_A;                      // Флаг доступа к меню создания/редактирования/удаления заграждения

const MAX_WALLS          = 64;                          // Максимальное кол-во заграждений на карте
const TASK_ID_SHOW_WALLS = 1024;

#if !defined NULLENT
    const NULLENT = -1;
#endif

new const FOLDER_NAME[] = "walls_data";                 // Папка в которой хранятся файлы с настройками для карт
new const FILE_FORMAT[] = "dat";                        // Формат файлов

new const ENT_CLASSNAME[] = "wall_ent";
new const ENT_SET_MODEL[] = "models/gib_skull.mdl";     // valve/models/gib_skull.mdl
new const SPRITE_BEAM[]   = "sprites/laserbeam.spr";    // valve/sprites/laserbeam.spr

enum {X, Y, Z};
enum _:TYPE {WALL_DEFAULT, ACTIVE_WALL, RED_WALL, YELLOW_WALL};
enum _:COLOR {R, G, B};

new const g_Coord[3][] = {"X", "Y", "Z"};
new const g_Color[TYPE][COLOR] = {
    {255, 255, 255},
    {0, 0, 255},
    {255, 0, 0},
    {255, 255, 0}
};

new Float:g_vecDefMins[3] = {-32.0, -32.0, -32.0};
new Float:g_vecDefMaxs[3] = {32.0, 32.0, 32.0};

new Float:g_WallPos[MAX_WALLS + 1][3];
new Float:g_WallMins[MAX_WALLS + 1][3];
new Float:g_WallMaxs[MAX_WALLS + 1][3];

new g_iEditorID = 0;
new g_iDirection = 0;
new g_iSetupUnits = 10;

new g_iWallsCount, g_iWallsMax, g_iWall_ID;
new g_iWallIndex[MAX_WALLS + 1];
new g_BeamSprite;
new g_MapName[32];

public plugin_precache()
{
    precache_model(ENT_SET_MODEL);
    g_BeamSprite = precache_model(SPRITE_BEAM);
}

public plugin_cfg()
{
    new szFileDir[128];

    get_localinfo("amxx_configsdir", szFileDir, charsmax(szFileDir));
    get_mapname(g_MapName, charsmax(g_MapName));

    formatex(szFileDir, charsmax(szFileDir), "%s/%s/%s.%s", szFileDir,FOLDER_NAME, g_MapName, FILE_FORMAT);

    switch(file_exists(szFileDir))
    {
        case 0:
        {
            server_print("[%s] Warning: there is no file with location of barriers for map ^"%s^"!", PLUGIN_NAME, g_MapName);
            return;
        }
        case 1: 
        {
            new iFile = fopen(szFileDir, "rt");
    
            if(iFile)
            {
                new szBuffer[128], szArgIndex[4];
                new szArgPosX[8], szArgPosY[8], szArgPosZ[8]; 
                new szArgMinsX[6], szArgMinsY[6], szArgMinsZ[6]; 
                new szArgMaxsX[6], szArgMaxsY[6], szArgMaxsZ[6];

                while(!feof(iFile))
                {
                    fgets(iFile, szBuffer, charsmax(szBuffer));
                    trim(szBuffer);

                    if(!(szBuffer[0]) || szBuffer[0] == ';' || szBuffer[0] == '#')
                        continue;

                    parse(szBuffer, szArgIndex, charsmax(szArgIndex),
                        szArgPosX, charsmax(szArgPosX), szArgPosY, charsmax(szArgPosY), szArgPosZ, charsmax(szArgPosZ),
                        szArgMinsX, charsmax(szArgMinsX), szArgMinsY, charsmax(szArgMinsY), szArgMinsZ, charsmax(szArgMinsZ),
                        szArgMaxsX, charsmax(szArgMaxsX), szArgMaxsY, charsmax(szArgMaxsY), szArgMaxsZ, charsmax(szArgMaxsZ)
                    );

                    UTIL_Vec_Set(g_WallPos[g_iWallsCount], str_to_float(szArgPosX), str_to_float(szArgPosY), str_to_float(szArgPosZ));
                    UTIL_Vec_Set(g_WallMins[g_iWallsCount], str_to_float(szArgMinsX), str_to_float(szArgMinsY), str_to_float(szArgMinsZ));
                    UTIL_Vec_Set(g_WallMaxs[g_iWallsCount], str_to_float(szArgMaxsX), str_to_float(szArgMaxsY), str_to_float(szArgMaxsZ));

                    g_iWallIndex[g_iWallsCount] = CreateNewWall(g_WallPos[g_iWallsCount], g_WallMins[g_iWallsCount], g_WallMaxs[g_iWallsCount]);
                    g_iWallsCount++;
                }

                fclose(iFile);
            }
        }
    }

    FindAllWalls();
    HideAllWalls();

    if(!g_iWallsCount)
    {
        server_print("[%s] Warning: file ^"%s^" is empty!", PLUGIN_NAME, szFileDir);
    } else {
        g_iWall_ID = g_iWallsMax;

        server_print("[%s] Success: %d barrier%s were uploaded to ^"%s^" map.", PLUGIN_NAME, g_iWallsMax, (g_iWallsMax > 1) ? "s" : "", g_MapName); 
    }
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("wallscreator", "PreOpen_WallsCreatorMenu", ACCESS_FLAG);

    register_menucmd(register_menuid("WallsCreator Menu"), 1023, "WallsCreator_MenuHandler");
    register_menucmd(register_menuid("WallsCreator EditMenu"), 1023, "WallsCreator_EditMenuHandler");
    register_menucmd(register_menuid("WallsCreator KillMenu"), 1023, "WallsCreator_KillMenuHandler");
}

public client_disconnected(iIndex)
{
    if(iIndex == g_iEditorID)
    {
        HideAllWalls();
        g_iEditorID = 0;
    }
}

public plugin_end()
    SaveAllWalls(0)

public task_ShowWallBox(iEnt)
{
    iEnt -= TASK_ID_SHOW_WALLS;

    if(!is_valid_ent(iEnt) || !g_iEditorID)
        return;

    new Float:vPos[3];

    entity_get_vector(iEnt, EV_VEC_origin, vPos);

    if(!is_in_viewcone(g_iEditorID, vPos) && iEnt != g_iWallIndex[g_iWall_ID])
        return;

    new Float:vEditorPos[3], Float:vReturn[3];

    entity_get_vector(g_iEditorID, EV_VEC_origin, vEditorPos);
    trace_line(NULLENT, vEditorPos, vPos, vReturn);

    if(iEnt == g_iWallIndex[g_iWall_ID])
        UTIL_VisualizeVector(vEditorPos[0], vEditorPos[1], vEditorPos[2] - 16.0, vPos[0], vPos[1], vPos[2], g_Color[RED_WALL]);

    new Float:dh = vector_distance(vEditorPos, vPos) - vector_distance(vEditorPos, vReturn)

    if(floatabs(dh) > 128.0 && iEnt != g_iWallIndex[g_iWall_ID])
        return;

    new iColor[3], Float:vMins[3], Float:vMaxs[3];

    entity_get_vector(iEnt, EV_VEC_mins, vMins);
    entity_get_vector(iEnt, EV_VEC_maxs, vMaxs);

    UTIL_Vec_Add(vMins, vPos, vMins);
    UTIL_Vec_Add(vMaxs, vPos, vMaxs);
    
    iColor[R] = (g_iWallIndex[g_iWall_ID] == iEnt) ? g_Color[ACTIVE_WALL][R] : g_Color[WALL_DEFAULT][R];
    iColor[G] = (g_iWallIndex[g_iWall_ID] == iEnt) ? g_Color[ACTIVE_WALL][G] : g_Color[WALL_DEFAULT][G];
    iColor[B] = (g_iWallIndex[g_iWall_ID] == iEnt) ? g_Color[ACTIVE_WALL][B] : g_Color[WALL_DEFAULT][B];
    
    UTIL_CreateBox(vMins, vMaxs, iColor);

    if(iEnt != g_iWallIndex[g_iWall_ID])
        return;

    switch(g_iDirection)
    {
        case X:     // X-координата
        {
            UTIL_VisualizeVector(vMaxs[0], vMaxs[1], vMaxs[2], vMaxs[0], vMins[1], vMins[2], g_Color[YELLOW_WALL]);
            UTIL_VisualizeVector(vMaxs[0], vMaxs[1], vMins[2], vMaxs[0], vMins[1], vMaxs[2], g_Color[YELLOW_WALL]);
            UTIL_VisualizeVector(vMins[0], vMaxs[1], vMaxs[2], vMins[0], vMins[1], vMins[2], g_Color[RED_WALL]);
            UTIL_VisualizeVector(vMins[0], vMaxs[1], vMins[2], vMins[0], vMins[1], vMaxs[2], g_Color[RED_WALL]);
        }
        case Y:     // Y-координата
        {
            UTIL_VisualizeVector(vMins[0], vMaxs[1], vMins[2], vMaxs[0], vMaxs[1], vMaxs[2], g_Color[YELLOW_WALL]);
            UTIL_VisualizeVector(vMaxs[0], vMaxs[1], vMins[2], vMins[0], vMaxs[1], vMaxs[2], g_Color[YELLOW_WALL]);            
            UTIL_VisualizeVector(vMins[0], vMins[1], vMins[2], vMaxs[0], vMins[1], vMaxs[2], g_Color[RED_WALL]);
            UTIL_VisualizeVector(vMaxs[0], vMins[1], vMins[2], vMins[0], vMins[1], vMaxs[2], g_Color[RED_WALL]);
        }
        case Z:     // Z-координата
        {
            UTIL_VisualizeVector(vMaxs[0], vMaxs[1], vMaxs[2], vMins[0], vMins[1], vMaxs[2], g_Color[YELLOW_WALL]);
            UTIL_VisualizeVector(vMaxs[0], vMins[1], vMaxs[2], vMins[0], vMaxs[1], vMaxs[2], g_Color[YELLOW_WALL]);
            UTIL_VisualizeVector(vMaxs[0], vMaxs[1], vMins[2], vMins[0], vMins[1], vMins[2], g_Color[RED_WALL]);
            UTIL_VisualizeVector(vMaxs[0], vMins[1], vMins[2], vMins[0], vMaxs[1], vMins[2], g_Color[RED_WALL]);
        }
    }
}

public PreOpen_WallsCreatorMenu(iIndex, iFlags)
{
    if(~get_user_flags(iIndex) & iFlags) 
    {
        console_print(iIndex, "* Недостаточно прав для использования данной команды!"); 
        return PLUGIN_HANDLED;
    }

    g_iEditorID = iIndex;

    FindAllWalls();
    ShowAllWalls();
    WallsCreator_BuildMenu(iIndex);

    return PLUGIN_HANDLED;
}

public WallsCreator_BuildMenu(iIndex)
{
    new szMenu[512], iLen;        
 
    new iKeys = MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_9|MENU_KEY_0;

    iLen = formatex(szMenu, charsmax(szMenu), "\w[\rWallsCreator Menu\w] Главное меню^n^n");

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wВсего заграждений на карте: \r%d^n", g_iWallsMax);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wВыбрано заграждение: \r%d^n^n", g_iWall_ID);

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%s Следующее заграждение^n", (g_iWall_ID < g_iWallsMax) ? "\r1. \w" : "\d1. ");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%s Предыдущее заграждение^n^n", (g_iWall_ID > 1) ? "\r2. \w" : "\d2. ");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%s Создать новое заграждение^n^n", (g_iWallsMax < MAX_WALLS) ? "\r3. \w" : "\d3. ");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%s Редактировать заграждение^n", is_valid_ent(g_iWallIndex[g_iWall_ID]) ? "\r4. \w" : "\d4. ");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%s Удалить заграждение^n^n", is_valid_ent(g_iWallIndex[g_iWall_ID]) ? "\r5. \w" : "\d5. ");

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \wСохранить настройки^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \wВыход");

    show_menu(iIndex, iKeys, szMenu, -1, "WallsCreator Menu");
}

public WallsCreator_MenuHandler(iIndex, iKey)
{
    switch(iKey) 
    {
        case 0:
        {
            g_iWall_ID = (g_iWall_ID < g_iWallsMax) ? ++g_iWall_ID : g_iWall_ID;
            WallsCreator_BuildMenu(iIndex);
        }
        case 1:
        {
            g_iWall_ID = (g_iWall_ID > 1) ? --g_iWall_ID : g_iWall_ID;
            WallsCreator_BuildMenu(iIndex);
        }
        case 2:
        {
            if(g_iWallsMax < MAX_WALLS)
            {
                new Float:vPos[3];

                entity_get_vector(iIndex, EV_VEC_origin, vPos);

                g_iWallIndex[g_iWallsCount] = CreateNewWall(vPos, g_vecDefMins, g_vecDefMaxs);
                g_iWall_ID = g_iWallsCount;

                ShowAllWalls();
                WallsCreator_BuildEditMenu(iIndex);
            }
        }
        case 3:
        {
            if(is_valid_ent(g_iWallIndex[g_iWall_ID]))
            {
                WallsCreator_BuildEditMenu(iIndex);
            } else {
                WallsCreator_BuildMenu(iIndex);
            }
        }
        case 4: WallsCreator_BuildKillMenu(iIndex);
        case 8:
        {
            SaveAllWalls(iIndex);
            WallsCreator_BuildMenu(iIndex);
            client_print_color(iIndex, 0, "[Server] Для корректной работы заграждений необходима смена карты!");
        }
        case 9: HideAllWalls();
    }
}

public WallsCreator_BuildKillMenu(iIndex)
{
    new szMenu[512], iLen;        
 
    new iKeys = MENU_KEY_0|MENU_KEY_1;

    iLen = formatex(szMenu, charsmax(szMenu), "\w[\rWallsCreator Menu\w] Удаление заграждения^n^n");

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \wУдалить выбранное заграждение^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \wОтмена, возврат в главное меню");

    show_menu(iIndex, iKeys, szMenu, -1, "WallsCreator KillMenu");
}

public WallsCreator_KillMenuHandler(iIndex, iKey)
{
    switch(iKey) 
    {
        case 0:
        {
            remove_entity(g_iWallIndex[g_iWall_ID]);
            FindAllWalls();

            g_iWall_ID = g_iWallsMax;
            WallsCreator_BuildMenu(iIndex);  

            client_print_color(iIndex, 0, "[Server] Заграждение успешно удалено.");        
        }
        case 9:
        {
            WallsCreator_BuildMenu(iIndex);
            client_print_color(iIndex, 0, "[Server] Чтобы изменения вступили в силу, не забудьте сохранить настройки!");
        }
    }
}

public WallsCreator_BuildEditMenu(iIndex)
{
    new szMenu[512], iLen;        
 
    new iKeys = MENU_KEY_0|MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_6;

    iLen = formatex(szMenu, charsmax(szMenu), "\w[\rWallsCreator Menu\w] Редактирование заграждения^n^n");
                                                                                                             
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \wИзменить ось редактирования: [\r%s\w]^n", g_Coord[g_iDirection]);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \wИзменить шаг редактирования: [\r%d Unit%s\w]^n^n", g_iSetupUnits, (g_iSetupUnits == 1) ? "": "s");

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3. \yУвеличить %s^n", g_iDirection == 1 ? "слева" : ((1 < g_iDirection) ? "сверху" : "спереди"));
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r4. \yУменьшить %s^n^n", g_iDirection == 1 ? "слева" : ((1 < g_iDirection) ? "сверху" : "спереди"));

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r5. \rУвеличить %s^n", g_iDirection == 1 ? "справа" : ((1 < g_iDirection) ? "снизу" : "сзади"));
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r6. \rУменьшить %s^n^n", g_iDirection == 1 ? "справа" : ((1 < g_iDirection) ? "снизу" : "сзади"));

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \wВернуться в главное меню");

    show_menu(iIndex, iKeys, szMenu, -1, "WallsCreator EditMenu");
}

public WallsCreator_EditMenuHandler(iIndex, iKey)
{
    new Float:vPos[3], Float:vMins[3], Float:vMaxs[3];

    entity_get_vector(g_iWallIndex[g_iWall_ID], EV_VEC_origin, vPos);
    entity_get_vector(g_iWallIndex[g_iWall_ID], EV_VEC_mins, vMins);
    entity_get_vector(g_iWallIndex[g_iWall_ID], EV_VEC_maxs, vMaxs);

    switch(iKey) 
    {
        case 0:
        {
            g_iDirection = (g_iDirection < 2) ? ++g_iDirection : 0;
            WallsCreator_BuildEditMenu(iIndex);
        }
        case 1:
        {
            g_iSetupUnits = (g_iSetupUnits < 100) ? g_iSetupUnits * 10 : 1;
            WallsCreator_BuildEditMenu(iIndex);
        }
        case 2:
        {
            vMins[g_iDirection] -= float(g_iSetupUnits) / 2.0;
            vMaxs[g_iDirection] += float(g_iSetupUnits) / 2.0;
            vPos[g_iDirection] += float(g_iSetupUnits) / 2.0;
    
            entity_set_vector(g_iWallIndex[g_iWall_ID], EV_VEC_origin, vPos);
            entity_set_size(g_iWallIndex[g_iWall_ID], vMins, vMaxs);

            WallsCreator_BuildEditMenu(iIndex);
        }
        case 3:
        {
            if((floatabs(vMins[g_iDirection]) + vMaxs[g_iDirection]) >= g_iSetupUnits)
            {
                vMins[g_iDirection] += float(g_iSetupUnits) / 2.0;
                vMaxs[g_iDirection] -= float(g_iSetupUnits) / 2.0;
                vPos[g_iDirection] -= float(g_iSetupUnits) / 2.0;
            }

            entity_set_vector(g_iWallIndex[g_iWall_ID], EV_VEC_origin, vPos);
            entity_set_size(g_iWallIndex[g_iWall_ID], vMins, vMaxs);

            WallsCreator_BuildEditMenu(iIndex);
        }
        case 4:
        {
            vMins[g_iDirection] -= float(g_iSetupUnits) / 2.0;
            vMaxs[g_iDirection] += float(g_iSetupUnits) / 2.0;
            vPos[g_iDirection] -= float(g_iSetupUnits) / 2.0;
    
            entity_set_vector(g_iWallIndex[g_iWall_ID], EV_VEC_origin, vPos);
            entity_set_size(g_iWallIndex[g_iWall_ID], vMins, vMaxs);

            WallsCreator_BuildEditMenu(iIndex);
        }
        case 5:
        {
            if((floatabs(vMins[g_iDirection]) + vMaxs[g_iDirection]) >= g_iSetupUnits)
            {
                vMins[g_iDirection] += float(g_iSetupUnits) / 2.0;
                vMaxs[g_iDirection] -= float(g_iSetupUnits) / 2.0;
                vPos[g_iDirection] += float(g_iSetupUnits) / 2.0;
            }

            entity_set_vector(g_iWallIndex[g_iWall_ID], EV_VEC_origin, vPos);
            entity_set_size(g_iWallIndex[g_iWall_ID], vMins, vMaxs);

            WallsCreator_BuildEditMenu(iIndex);
        }
        case 9:
        {
            WallsCreator_BuildMenu(iIndex);
            client_print_color(iIndex, 0, "[Server] Чтобы изменения вступили в силу, не забудьте сохранить настройки!");
        }
    }
}

CreateNewWall(Float:vPos[3], Float:vMins[3], Float:vMaxs[3])
{
    new iEnt = create_entity("info_target");

    entity_set_string(iEnt, EV_SZ_classname, ENT_CLASSNAME);
    entity_set_model(iEnt, ENT_SET_MODEL);
    entity_set_origin(iEnt, vPos);
    entity_set_int(iEnt, EV_INT_movetype, MOVETYPE_PUSH);

    if(g_iEditorID)
    {
        entity_set_int(iEnt, EV_INT_solid, SOLID_NOT);
    } else {
        entity_set_int(iEnt, EV_INT_solid, SOLID_BBOX);
    }

    entity_set_size(iEnt, vMins, vMaxs);
    set_entity_visibility(iEnt, 0);

    return iEnt;
}

FindAllWalls()
{
    new iEnt = NULLENT;
    g_iWallsCount = 0;

    while((iEnt = find_ent_by_class(iEnt, ENT_CLASSNAME)))
        g_iWallIndex[++g_iWallsCount] = iEnt;

    g_iWallsMax = g_iWallsCount;
    g_iWallsCount += 1; 
}

HideAllWalls()
{
    g_iEditorID = 0;

    for(new i; i < g_iWallsCount; i++)
    {
        if(is_valid_ent(g_iWallIndex[i]))
        {
            entity_set_int(g_iWallIndex[i], EV_INT_solid, SOLID_BBOX);
            remove_task(TASK_ID_SHOW_WALLS + g_iWallIndex[i]);
        }
    }
}

ShowAllWalls()
{
    FindAllWalls();
    
    for(new i; i < g_iWallsCount; i++)
    {
        if(is_valid_ent(g_iWallIndex[i]))
        {
            if(task_exists(TASK_ID_SHOW_WALLS + g_iWallIndex[i]))
                remove_task(TASK_ID_SHOW_WALLS + g_iWallIndex[i]);

            entity_set_int(g_iWallIndex[i], EV_INT_solid, SOLID_NOT);
            set_task(0.2, "task_ShowWallBox", TASK_ID_SHOW_WALLS + g_iWallIndex[i], _, _, "b");
        }
    }
}

SaveAllWalls(iIndex)
{
    new szFileDir[128], szBuffer[128];

    get_localinfo("amxx_configsdir", szFileDir, charsmax(szFileDir));

    formatex(szFileDir, charsmax(szFileDir), "%s/%s/", szFileDir,FOLDER_NAME);

    if(!dir_exists(szFileDir))
        mkdir(szFileDir);

    formatex(szFileDir, charsmax(szFileDir), "%s/%s.%s", szFileDir, g_MapName, FILE_FORMAT);

    if(file_exists(szFileDir))
        delete_file(szFileDir);

    FindAllWalls();
    
    formatex(szBuffer, charsmax(szBuffer), "#^n\
        # File was created for %s^n\
        #^n\
        # <Wall Index> <Position X Y Z> <Mins X Y Z> <Maxs X Y Z>^n\
        #^n", g_MapName
    );
    write_file(szFileDir, szBuffer);

    for(new i; ++i < g_iWallsCount;)
    {
        new Float:vPos[3], Float:vMins[3], Float:vMaxs[3]

        entity_get_vector(g_iWallIndex[i], EV_VEC_origin, vPos);
        entity_get_vector(g_iWallIndex[i], EV_VEC_mins, vMins);
        entity_get_vector(g_iWallIndex[i], EV_VEC_maxs, vMaxs);

        formatex(szBuffer, charsmax(szBuffer), "%d %.1f %.1f %.1f %.0f %.0f %.0f %.0f %.0f %.0f", 
            i, vPos[0], vPos[1], vPos[2], vMins[0], vMins[1], vMins[2], vMaxs[0], vMaxs[1], vMaxs[2]
        );

        write_file(szFileDir, szBuffer);
    }
    
    if(iIndex > 0)
    {
        client_print_color(iIndex, 0, "[Server] Заграждения для текущей карты сохранены в файле ^"^4%s/%s.%s^1^".", FOLDER_NAME, g_MapName, FILE_FORMAT);
    } else if(iIndex == 0) {
        server_print("[%s] Map Change: All created barriers are stored in file ^"%s/%s.%s^".", PLUGIN_NAME, FOLDER_NAME, g_MapName, FILE_FORMAT);
    }
}

stock UTIL_CreateBox(const Float:vecMins[], const Float:vecMaxs[], Color[3])
{
    UTIL_VisualizeVector(vecMaxs[0], vecMaxs[1], vecMaxs[2], vecMins[0], vecMaxs[1], vecMaxs[2], Color);
    UTIL_VisualizeVector(vecMaxs[0], vecMaxs[1], vecMaxs[2], vecMaxs[0], vecMins[1], vecMaxs[2], Color);
    UTIL_VisualizeVector(vecMaxs[0], vecMaxs[1], vecMaxs[2], vecMaxs[0], vecMaxs[1], vecMins[2], Color);
    UTIL_VisualizeVector(vecMins[0], vecMins[1], vecMins[2], vecMaxs[0], vecMins[1], vecMins[2], Color);
    UTIL_VisualizeVector(vecMins[0], vecMins[1], vecMins[2], vecMins[0], vecMaxs[1], vecMins[2], Color);
    UTIL_VisualizeVector(vecMins[0], vecMins[1], vecMins[2], vecMins[0], vecMins[1], vecMaxs[2], Color);
    UTIL_VisualizeVector(vecMins[0], vecMaxs[1], vecMaxs[2], vecMins[0], vecMaxs[1], vecMins[2], Color);
    UTIL_VisualizeVector(vecMins[0], vecMaxs[1], vecMins[2], vecMaxs[0], vecMaxs[1], vecMins[2], Color);
    UTIL_VisualizeVector(vecMaxs[0], vecMaxs[1], vecMins[2], vecMaxs[0], vecMins[1], vecMins[2], Color);
    UTIL_VisualizeVector(vecMaxs[0], vecMins[1], vecMins[2], vecMaxs[0], vecMins[1], vecMaxs[2], Color);
    UTIL_VisualizeVector(vecMaxs[0], vecMins[1], vecMaxs[2], vecMins[0], vecMins[1], vecMaxs[2], Color);
    UTIL_VisualizeVector(vecMins[0], vecMins[1], vecMaxs[2], vecMins[0], vecMaxs[1], vecMaxs[2], Color);
}

/* Thanks wopox1337 for stock (https://dev-cs.ru/threads/222/#post-8937) */
stock UTIL_VisualizeVector(Float:vStartX, Float:vStartY, Float:vStartZ, Float:vEndX, Float:vEndY, Float:vEndZ, iColor[3])
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(floatround(vStartX));
    write_coord(floatround(vStartY));
    write_coord(floatround(vStartZ));
    write_coord(floatround(vEndX));
    write_coord(floatround(vEndY));
    write_coord(floatround(vEndZ));
    write_short(g_BeamSprite);
    write_byte(1);           // Стартовый кадр
    write_byte(1);           // Скорость анимации 
    write_byte(2);           // Время существования/life in 0.1's 
    write_byte(6);           // Толщина луча
    write_byte(0);           // Искажение 
    write_byte(iColor[0]);   // Цвет красный 
    write_byte(iColor[1]);   // Цвет зеленый
    write_byte(iColor[2]);   // Цвет синий
    write_byte(200);         // Яркость 
    write_byte(0);           // Скорость 
    message_end();
}

stock UTIL_Vec_Add(const Float:Vec1[], const Float:Vec2[], Float:Out[])
{
    Out[0] = Vec1[0] + Vec2[0];
    Out[1] = Vec1[1] + Vec2[1];
    Out[2] = Vec1[2] + Vec2[2];
}

stock UTIL_Vec_Set(Float:Vec[], Float:x, Float:y, Float:z)
{
    Vec[0] = x;
    Vec[1] = y;
    Vec[2] = z;
}
