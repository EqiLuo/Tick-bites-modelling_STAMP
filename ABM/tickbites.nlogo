extensions [ gis csv ]

breed [ residents resident ]
breed [ tourists tourist ]

turtles-own [
  age
  activity activityLandID
  vulnerability exposure
  bite-risk tickbite-status last-bite-day
]
tourists-own [
  stay-duration stay
]
patches-own [
  landuse
  patch-bite-count
]
globals [
  landuse-list landuse-dataset shape-dataset
  precipitation-data precipitation
  hazard-data hazard
  month
  age-list activity-list activityLandID-list exposure-list
  bite-count
  output-file
]
; landuse-list [20 60 61 62] 20: residential; 60: forest; 61: dunes; 62: others
; activity-list [1 2 3 4 5 6 7 8]
; 1: walking; 2: gardening; 3: playing; 4: dog walking; 5: picnic; 6: professional garden maintenance; 7: others; 8: indoors
; age-list [1 2 3] 1: young (0-18); 2: adult (19-64); 3: elderly (>65)

to setup
  clear-all
  setup-environment
  setup-agents
  ; ------ Set initial bite-count ------
  set bite-count 0
  ; ------ Read daily precipitation values ------
  set precipitation-data csv:from-file "input/preci_Ede201516_nodate.csv"

  ; ------ Read monthly tick activity (hazard) values ------
  set hazard-data csv:from-file "input/tick_activity_2015to2016.csv"
  reset-ticks
end

to setup-agents
  set activity-list [1 2 3 4 5 6 7 8]
  set age-list [1 2 3]

  ; ------ Create residents ------
  ; initial-number-residents is set by users in Interface tab
  ; In Ede, there are 112410 residents in total
  create-residents initial-number-residents

  ; ------ Set the age of residents ------
  ; The percentages of young age group, and adult age group are set by users in Interface tab
  ask residents [
    ifelse random 100 < percent-young [
      set age item 0 age-list ] ; in Ede the precentage of young people (0-18) is 22%
      [ ifelse random 100 < percent-adult [
          set age item 1 age-list ] ; be careful: the percent-adult is the relative percent of adults in adults and elderly people (young people excluded); in Ede it is 78%
        [ set age item 2 age-list ]] ; set the age of all other people as elderly
  ]

  ; ------ Get the vulnerability of people of each age group ------
  ; The relative vulnerability of each age group is calculated based on ground truth data
  ask residents with [ age = 1 ] [ set vulnerability 25 ] ;;vulnerability value, sensitivity test, compare with literature
  ask residents with [ age = 2 ] [ set vulnerability 63 ]
  ask residents with [ age = 3 ] [ set vulnerability 12 ]

  ; ------ Set the default last-bite-day ------
  ask residents [
    set last-bite-day 9999 ]

  ; ------ Move residents to residential area ------
  ask residents [
    move-to one-of patches with [landuse = 20]
    set color blue
    set shape "person" ]

end

to setup-environment
  ; ------ Load land use map of the study area ------
  set landuse-dataset gis:load-dataset "/input/ede_ascii.asc" ; Note: the data and the scripts must be in the same folder
  gis:set-world-envelope (gis:envelope-of landuse-dataset)
  set-patch-size 5
  gis:apply-raster landuse-dataset landuse

  ; ------ Set the layout of map ------
  ; 20 : residential; 60 : forest; 61 : dunes/sand; 62 : other
  ask patches [
    if landuse = 20 [
      set pcolor red]
    if landuse = 60 [
      set pcolor green]
    if landuse = 61 [
      set pcolor yellow]
    if landuse = 62 [
      set pcolor grey]
  ]

  set shape-dataset gis:load-dataset "input/Ede_shape.shp" ;;add the boundary of study area
  gis:set-drawing-color white
  gis:draw shape-dataset 1

end

to go

  ; ------ Set daily precipitation value ------
  set precipitation item 0 item ticks precipitation-data

  ; ------ Set monthly hazard value ------
  set month ceiling ( (ticks + 1) / 30 )
  if ticks mod 30 = 0 [
  ; hazard is the ordered monthly tick activity data, starting from January
    set hazard item 0 item (month - 1) hazard-data
  ]

  ; ------ Create new tourists ------
  ; Peak seasons are from April to October, and off seasons are from November to March
  ; Daily tourist number is set by the user in Interface tab
  ifelse ticks mod 360 > 90 and ticks mod 360 < 301 [
    create-tourists daily-tourists-peak ] ; in Ede, the daily tourist number in peak seasons is 27900
    [create-tourists daily-tourists-off ] ; in Ede, the daily tourist number in off seasons is 20700

  ; ------ Set the stay duration of new tourists ------
  ask tourists with [ stay-duration < 1 ] [
    ; stay is the number of days a tourist has stayed in this area
    ; set the initial stay as 0
    set stay 0
    ; ------ Set the default last-bite-day of new tourists ------
    set last-bite-day 9999
    ; ------ Set the age and vulnerability of new tourists ------
    ifelse random 100 < 18 [
      set age item 0 age-list
      set vulnerability 25] ; percent of young tourists is 18%
      [ ifelse random 100 < 80 [
          set age item 1 age-list
          set vulnerability 63] ; percent of adult tourists in adults and elderly tourists is 66%/(100%-18%)= 80%
        [ set age item 2 age-list
          set vulnerability 12]] ;; set the age of other tourists as elderly

    ; ------ Set the stay-duration of new tourists ------
    ; The percentage of tourists who stay for 2 days, 5 days are set by the user in Interface tab
    ifelse random 100 < percent-2days [
      set stay-duration 2 ]
        [ ifelse random 100 < percent-5days [
            set stay-duration 5 ]
        [ set stay-duration 9 ]]

    ; ------ Ask new tourists to first move to any place in the study area randomly ------
    move-to one-of patches with [ landuse > 0 ]
    set color yellow
    set shape "person"
  ]

  ; ------ Reset initial tick bite status as False everyday ------
  ask turtles [set tickbite-status False]

  ; ------ Set activity of agents ------
  assign-activity

  ; ------ Ask people to move to land use type based on the activity type ------
  go-movement

  ; ------ Determine if an agent gets a tick bite ------
  tick-bite

  ; ------ Count the total tick bites ------
  count-bites

  ; ------ Write the information of agents into file ------
  write-to-file

  ; ------ Count the cumulated tick bites in each patch ------
  patch-bite-counts

  ; ------ Ask people who get tick bites to learn to be aware of ticks ------
  learn

  ; ------ People who got tick bites a month ago forget to be aware of ticks again ------
  forget

  ; ------ Ask residents to go back home ------
  ask residents [ move-to one-of patches with [landuse = 20] ]

  ; ------ Update the stay of tourists ------
  ask tourists [
    set stay stay + 1 ]
  ; ------ Tourists who stay long enough leave the city ------
  ask tourists with [ stay = stay-duration ] [
    die ]

  tick

  ; ------ After the model runs for 2 years, export the patch-bite-count map and stop the model ------
  ; adjust the number 720 to the number of days of the simulation period
  if ticks mod 720 = 0 [
    set output-file gis:patch-dataset patch-bite-count
    ; Report a new raster whose cells correspond directly to NetLogo patches, and whose cell values consist of the patch-bite-count
    gis:store-dataset output-file "patch_biteCount_ascii.asc"
    stop ]
end

 ; ------ Set activity of agents ------
to assign-activity
  ; When it does not rain, set activity of tourists randomly in 1 walking, 3 playing; 5 picnic, and 7 others
  ; On weekends set the activity of residents randomly in 7 outdoor activity types
  ; except that young people do not do gardening and professional garden maintenance
  ; On weekdays residents do indoor activity
  ; When it rains, all people do indoor activity
  ifelse precipitation < 50 [
    ask tourists [
      set activity one-of [1 3 5 7]]
    ifelse ticks mod 7 = 0 or ticks mod 7 = 6 [
      ask residents with [ age = 1 ] [
        set activity one-of [ 1 3 4 5 7 ]]
      ask residents with [ age = 2 or age = 3 ] [
        set activity one-of [ 1 2 3 4 5 6 7 ]]]
    [ask residents [set activity 8]]] ; On weekdays ask residents to do indoor activity
    [ask turtles [
    set activity 8 ]]
end

; ------ Ask agents to move to land use type based on the weather and activity type, calculate the exposure ------
to go-movement
  ; ------ Move the people if it does not rain ------
  ; residents who do indoor activity and do gardening move in the residential area
  ; tourists who do indoor activity stay where they are
  ask residents with [activity = 8 or activity = 2] [
    move-to one-of patches with [landuse = 20]]
  ; people who have other activities move to any land use type randomly
  ask turtles with [activity != 8 and activity != 2] [
    move-to one-of patches with [landuse > 0 ]]

  ; ------ Set activityLandID-list (combination of every activity and every land use type)------
  set activityLandID-list [ 201	202	203	204	205	206	207	208 601	602	603	604	605	606	607	608 611	612	613	614	615	616	617	618 621	622	623	624	625	626	627 628 ]
  ; get the activityLandID of people based on activity and land use
  ask turtles [
    set activityLandID 10 * [ landuse ] of patch-here + activity
  ]
  ; ------ Set exposure-list ------
  ; each exposure number respresents the relative risk of each activity in each land use type
  ; the exposure is calculated based on ground truth tick bites data
  ; the order of the list is the same as the order of activitylandID
  set exposure-list [ 6.70	21.19	6.05	1.52	0.57	0.97	1.35	0 36.12	1.31	7.79	4.02	1.75	1.80	2.61	0 3.10	0.30	0.72	0.17	0.22	0.25	0.28	0 0.21	0.05	0.12	0.14	0.07	0.05	0.58 0]
  ; set corresponding exposure of people according to their activityLandID in the activityLandID list
  ask turtles [
    set exposure item position activityLandID activityLandID-list exposure-list]

end

  ; ------ Determine if an agent gets a tick bite ------
to tick-bite
  ; ------ Calculate the risk % of getting a tick bite ------
  ask turtles [
    set bite-risk hazard * exposure * vulnerability / 1000 ]
    ; bite-risk varies from 0 to 89
  ; ------ Determine a tick bite ------
  ask turtles [
    ; the chance of getting a tick bite is: chance = bite-risk % * general probability
    ; the general probability is set by the user, and calibrated by ground truth data
    if random 100 < bite-risk [
      if random-float 1 < probability [
        set tickbite-status True
        ; ------ Record the last bite day ------
        set last-bite-day ticks ]
  ]]
end

  ; ------ Count the total tick bites ------
to count-bites
  set bite-count bite-count + count turtles with [tickbite-status = True]
end

  ; ------ Write the information of agents into file ------
to write-to-file ;;
  file-open "tickbite.txt"
  foreach sort turtles  [x-turtle ->
    ask x-turtle [
      ;;write the information into file based on the needs of post-analysis
      ;;file-write ticks
      file-write month
      ;;file-write (word self) file-write xcor file-write ycor
      file-write age
      file-write activity file-write landuse
      ;;file-write activityLandID
      ;;file-write bite-risk
      file-write tickbite-status
      FILE-TYPE "\n"
    ]
  ]
  ; file-print " " ;followed by the carriage return;
  file-close
end

  ; ------ Ask people who get tick bites to learn to be aware of ticks by decreasing their vulnerability------
to learn
  ask turtles with [ tickbite-status = True and vulnerability > 0 ] [
  set vulnerability vulnerability - 1 ]
end

  ; ------ People who got tick bites a month ago forget to be aware of ticks again ------
to forget
  ask turtles with [ last-bite-day != 0 and ticks - last-bite-day = 30 ] [
  set vulnerability vulnerability + 1 ]
end

  ; ------ Count the cumulated tick bites in each patch ------
to patch-bite-counts
  ask patches [
    set patch-bite-count patch-bite-count + count turtles-here with [tickbite-status = True]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
564
10
1077
524
-1
-1
5.0
1
10
1
1
1
0
1
1
1
-50
50
-50
50
1
1
1
ticks
30.0

BUTTON
10
11
76
44
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
11
57
74
90
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
10
199
92
244
NIL
bite-count
17
1
11

PLOT
0
251
200
471
Number of total bites
day
number of bites
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"pen-0" 1.0 0 -7858858 true "" "plot bite-count"

PLOT
203
195
555
469
Number of new bites
day
number of new bites
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count turtles with [tickbite-status = True]"

SLIDER
339
11
548
44
daily-tourists-peak
daily-tourists-peak
0
30000
27900.0
1
1
NIL
HORIZONTAL

SLIDER
101
56
317
89
percent-young
percent-young
0
100
22.0
1
1
NIL
HORIZONTAL

SLIDER
102
101
317
134
percent-adult
percent-adult
0
100
78.0
1
1
NIL
HORIZONTAL

SLIDER
101
10
317
43
initial-number-residents
initial-number-residents
0
200000
112410.0
100
1
NIL
HORIZONTAL

SLIDER
340
101
547
134
percent-2days
percent-2days
0
100
51.0
1
1
NIL
HORIZONTAL

SLIDER
340
144
547
177
percent-5days
percent-5days
0
100
65.0
1
1
NIL
HORIZONTAL

SLIDER
339
56
547
89
daily-tourists-off
daily-tourists-off
0
30000
20700.0
1
1
NIL
HORIZONTAL

PLOT
1028
46
1228
196
precipitation
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot precipitation"

PLOT
1030
293
1230
443
tick activity
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot hazard"

SLIDER
102
147
318
180
probability
probability
0
1
0.005
0.0001
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

This tick bites model aims to simulate the tick bites in the study area. The goal of this simulation is to investigate the impact of tick dynamics and human activity on the chances of getting a tick bite. This model is expected to reproduce the spatial and temporal patterns of tick bites, such as the peak and off seasons of tick bites, and spatial variety in different land use types.

## HOW IT WORKS

This simulation has two breeds of agents: residents, and tourists. Residents stay in the study area, while tourists come and stay for a few days and leave this area. The goal of the residents and tourists is to do different outdoor and indoor activities based on the condition of holidays and their preferences, and then move to the relevant land use type. The agent will get a tick bite if their risk is relatively high.

This simulation of tick bites is based on the formula of risk (R): R = Hazard * Exposure * Vulnerability. Hazard is approximated by the tick activity. Exposure is determined by the activity type of people and land use type where people do this activity. It is assumed that different types of activity in different land use type have different exposure (or relative risk of getting a tick bite). Vulnerability is determined by the characteristics of people, including the age group, and the awareness of ticks.

The agents adapt their activities and movements according to the weather conditions. When it rains hard, all agents will stay indoors. 

Agents also change their own awareness of ticks in response to their tick bite status. When they get tick bites, they will learn to be more aware of ticks, and get lower vulnerability. But the learning outcome expires when they have not gotten tick bites for a long time since the last one. They will forget to be careful about ticks, and their vulnerability will increase again. 

This model will not be used to predict the exactly correct number of tick bites every year. The purpose is to explore the patterns of tick bites and explain the factors that influence the patterns.
## HOW TO USE IT

To use this model, first prepare the input data:

1. Spatial data: land use map; study area boundary map.
2. Hazard data: the monthly tick activity data.
3. Temperature data: the daily precipitation data.
4. Agent initialization: the number of residents, percentage of young and adult age group; the number of new tourists every day in peak and off seasons, the percentage of 2-day and 5-day stay duration.
5. Parameters in simulation: vulnerability of each age group, all activity types, exposure of each activity in each land use type, and probability of getting a tick bite. 

Next, change the data directory and load the input data. 

And then edit the values and parameters. The value of agent initialization variables and probability of getting a tick bite can be changed in Interface tab. Other parameters can be edited in Code tab. Adjust the length of simulation period in Code tab.

Next, click setup button, and click go button.

### setup
Set up the initial condition of agents and environment by clicking setup. 

In this model, setup includes setting up the residents in this area, land use map, and load the tick activity and precipitation data.
### go
Go is a "forever" button. It repeats along with every tick automatically, and can be paused and continued by the user. 

In this model, in every go, new tourists are created, and all agents are assigned activities, move to relevant land use type, and get tick bites based on the risk and probability.
### slider: initial-number-residents
The value of initial-number-residents is the total population in the study area. It is set by the user. 

For example, in Ede, there are 112410 residents in total.
### slider: percent-young
The percent-young is the percentage of young age group ( 0 - 18 years old) among all the people. It is set by the user based on the age distribution in the study area. 

For example, in Ede, there are 24608 young people, so the percentage is 24609/112410 = 22%.
### slider: percent-adult
The percent-adult is the percentage of adult age group ( 19 - 64 years old) among adult and elderly people, excluding young people. It is set by the user based on the age distribution in the study area.
 
For example, in Ede, there are 68380 adult people, so the percentage is 68380/(112410-24609) = 22%.
### slider: daily-tourists-peak
The daily-tourists-peak is the average daily new tourist population in peak seasons ( from April to October). It is set by the user based on the study area.

For example, in Ede, the estimated number of daily new tourists in peak seasons is 27900. 
### slider: daily-tourists-off
The daily-tourists-off is the average daily new tourist population in off seasons ( from November to March). It is set by the user based on the study area.

For example, in Ede, the estimated number of daily new tourists in off seasons is 20700.
### slider: percent-2days
The percent-2days is the percentage of tourists who stay for 2 days among all the tourists. It is set by the user in Interface tab based on the study area.

For example, in Ede, the percentage of tourists who stay for 2 days is 4570000/9000000 = 51%.
### slider: percent-5days
The percent-5days is the percentage of tourists who stay for 5 days among all other tourists except for the tourists who stay for 2 days. It is set by the user in Interface tab based on the study area.

For example, in Ede, the percentage of tourists who stay for 5 days is 2870000/(9000000-4570000) = 65%.
### slider: probability
The probability is the general chance of getting a tick bite besides the tick bite-risk. This is set by the user, and has to be calibrated based on the ground truth data.

For example, in Ede, after setting the bite-risk and run the model, there are 4 million tick bites during 2015 and 2016 in the end, but there are only 20000 tick bites in reality. So the probability is set to be 20000/4000000 = 0.005.  
### plot: precipitation
Precipitation plot shows the loaded daily weather input data. People do not move to new places when it rains hard.
### plot: tick activity
The tick activity plot shows the monthly tick activity input data.
### monitor: bite-count
The bite-count shows the number of cumulative total number of tick bites. It updates every day.
### plot: Number of new bites
The number of new bites shows daily number of new tick bites.
### plot: Number of total bites
The number of total bites shows the cumulative total number of tick bites.
## THINGS TO NOTICE
Before running the model, please make sure that the input data and the scripts are in the same working directory.

While running the model, please note the movement of agents on the land use map, and the temporal variation of number of new bites, such as the difference of weekdays and weekends, the influence of precipitation, the seasonal variation of tick bites, which is caused by the monthly tick activity variation. 
## THINGS TO TRY

Move the slider of the number of residents, tourists, the percentage of age group, or the stay duration percentage. Check the difference in daily new bites and total bite count.

## EXTENDING THE MODEL


To adapt this model to your study area, please first change the input data, and then customize all the initialzation variables, like vulnerability of each age group, and the percentage of tourists with different stay duration. Then according to the activity and land use distribution of tick bites in your study area, edit the activity list, land use list, activityLandID list, and exposure list. 

The learning rate and forgeting rate (how much the vulnerability changes every time in "learn" and "forget") can also be adjusted.

To make this model more detailed, the activity type can be assigned to different age groups based on their preferences, and seasonal variations can also be considered. The land use type that agent move to can also be adjusted more accurately based on the activity preferences in reality.

To explore more patterns of tick bites, the output can be adjusted based on your needs.

## RELATED MODELS

As the input of this model, tick activity is the hazard that causes the tick bite risk. Tick activity can be influenced by environmental factors, land use types, etc. Further tick activity model can be found in other studies, such as tick dynamics modelling by Raúl Zurita-Milla.

## CREDITS AND REFERENCES

### Residents population

StatLine - Population on January 1 and average; gender, age and region. (2020). Retrieved June 19, 2020, from https://opendata.cbs.nl/statline/#/CBS/nl/dataset/03759ned/table?ts=1591732275230

### Tourist population
Kok, J. (2019). Simulating tick bites in the Netherlands using agent-based modelling (Master's thesis).

Gelderman, C. (2011). Feiten en cijfersoOver de vrijetijdssector in Overijssel 2011. https://doi.org/10.1007/978-90-313-6623-1_2

StatLine - Hotels; guests, overnight stays, country of residence, region. (2020). Retrieved June 19, 2020, from https://opendata.cbs.nl/#/CBS/en/dataset/82061ENG/table

### Model calibration

Lyme disease RIVM. (2019). Retrieved June 20, 2020, from https://www.rivm.nl/ziekte-van-lyme

### Tick dynamics model

Garcia-Martí, I., Zurita-Milla, R., Van Vliet, A. J., & Takken, W. (2017). Modelling and mapping tick dynamics using volunteered observations. International journal of health geographics, 16(1), 41.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="uncertainty_experiment" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="365"/>
    <metric>bite-count</metric>
  </experiment>
  <experiment name="run_times_experiment" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="365"/>
    <metric>bite-count</metric>
  </experiment>
  <experiment name="experiment_sensitivity" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="365"/>
    <metric>bite-count</metric>
    <enumeratedValueSet variable="initial-number-residents">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="initial-number-tourists" first="0" step="100" last="1000"/>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
