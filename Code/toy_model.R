library(tidyverse)
library(mvtnorm)
source('Code/functions.R')
# Rcpp::sourceCpp("Code/getBestSpp.cpp")

# Model parameters --------------------------------------------------------

spp.names <- c('crab', 'salmon', 'groundfish')
fleets <- c('crab', 'salmon', 'groundfish', 'crab-salmon', 'crab-groundfish', 'crab-salmon-groundfish')

wks_per_yr <- 52
nyrs <- 50
npops <- length(spp.names)
nfleets <- length(fleets)
ships_per_fleet <- rep(1, nfleets) * 67
nships <- max(ships_per_fleet)
# fleet_permits <- cbind(c(1,0,0), # crab fleet 
#                        c(0,1,0), # salmon fleet
#                        c(1,1,0)) # crab-salmon fleet

fleet_permits <- cbind(c(1,0,0), # crab fleet 
                       c(0,1,0), # salmon fleet
                       c(0,0,1), # groundfish fleet
                       c(1,1,0), # crab-salmon fleet
                       c(1,0,1), # crab-groundfish fleet
                       c(1,1,1)) # crab-salmon-groundfish fleet
dimnames(fleet_permits) <- list(spp = spp.names, fleet = fleets)
names(ships_per_fleet) <- fleets

# Is a list so that other season options can be included within a single simulation. If season is constant, list is length 1.
pop_seasons <- list(matrix(1, nrow = npops, ncol = wks_per_yr, dimnames = list(spp = spp.names, wk = NULL)))

# crab (spp. 1) season = Dec. 1 - Aug. 14
# Assume yr starts Dec. 1
pop_seasons[[1]]['crab', 37] <- 1
# pop_seasons[[1]]['crab', 37] <- 0.7
pop_seasons[[1]]['crab', 38:wks_per_yr] <- 0
# pop_seasons[[1]]['crab', 1:4] <- 0 # HAB closure

# salmon (spp. 2) season = May 1 - Oct. 31 (actually more complicated)
pop_seasons[[1]]['salmon', 1:21] <- 0
# pop_seasons[[1]]['salmon', 22] <- 0.3
pop_seasons[[1]]['salmon', 22] <- 0
pop_seasons[[1]]['salmon', 47] <- 1
# pop_seasons[[1]]['salmon', 47] <- 0.7
pop_seasons[[1]]['salmon', 48:wks_per_yr] <- 0;

catchability <- c(.0005, .00005, 0);
# proportion of stock that will be caught by one fleet/ship during one week
# of fishing
# groundfish gets set below

price <- c(1, 1, 1)
avg_rec <- c(1, 1, 1) # groundfish must be set to 1, this is the mean of the multiplicative errors in that case
avg_wt <- c(1, 1, 1)

weight_cv <- 0 # sqrt(log(0.2^2+1))
recruit_cv <- sqrt(log(0.6^2+1))
recruit_ar <- c(.3,.3, .3)
recruit_corr <- 0

fixed_costs <- c(.0018, .0001, .00002) #c(.0025, .0001, .00002)
cost_per_trip <- rep(NA, npops)
cost_cv <- sqrt(log(.15^2+1))
cost_corr <- 0.7

names(catchability) <- names(price) <- names(avg_rec) <- names(avg_wt) <- names(fixed_costs) <- names(cost_per_trip) <- 
  names(recruit_ar) <- spp.names

salmon_tac_rule <- 0.3

crab_price_cutoff <- 0.1
crab_price_pars <- c(2,10)

sim_pars <- list(spp.names = spp.names, fleets = fleets, wks_per_yr = wks_per_yr, nyrs = nyrs, npops = npops,
                 nfleets = nfleets, ships_per_fleet = ships_per_fleet, nships = nships, fleet_permits = fleet_permits,
                 pop_seasons = pop_seasons, catchability = catchability, price = price, avg_rec = avg_rec, 
                 avg_wt = avg_wt, weight_cv = weight_cv, recruit_cv = recruit_cv, recruit_ar = recruit_ar, 
                 recruit_corr = recruit_corr, ind_pops = 0, fixed_costs = fixed_costs, cost_per_trip = cost_per_trip, 
                 cost_cv = cost_cv, cost_corr = cost_corr, salmon_tac_rule = salmon_tac_rule,
                 crab_price_cutoff = crab_price_cutoff, crab_price_pars = crab_price_pars, season_prob = 1)

# Crab demand function. Currently hard-coded into simulation function. This is not used. -------

# Assume price = 1 first week, everyone fishes
min_price <- 1 # Note this is hard-coded into the calculations right now!

# At 20% of initial catch, prices are 30% higher
price_increase <- 0.3
ref_catch <- 0.2

# linear demand function
beta_price <- price_increase/((1-ref_catch) * catchability['crab'] * avg_rec['crab'] * avg_wt['crab'] *
                                sum(ships_per_fleet[c('crab', 'crab-salmon')]))

alpha_price <- 1 + beta_price * catchability['crab'] * avg_rec['crab'] * avg_wt['crab'] * 
  sum(ships_per_fleet[c('crab', 'crab-salmon')])

# log function. Price increases too steeply at low catches.
beta_price <- price_increase/(log(catchability['crab'] * avg_rec['crab'] * avg_wt['crab'] *
                                    (ships_per_fleet['crab'] + ships_per_fleet['crab-salmon'])) -
                                log(ref_catch * catchability['crab'] * avg_rec['crab'] * avg_wt['crab'] *
                                      (ships_per_fleet['crab'] + ships_per_fleet['crab-salmon'])))
alpha_price <- 1 + beta_price * log(catchability['crab'] * avg_rec['crab'] * avg_wt['crab'] *
                                      (ships_per_fleet['crab'] + ships_per_fleet['crab-salmon']))

# Calculating variable costs ----------------------------------------------

xx <- uniroot(calc_var_cost, interval = c(-20,0),
              cost_cv = cost_cv, recruits = avg_rec['crab'], wt_at_rec = 1, price = c(2,10), #price['crab'], c(alpha_price, beta_price),
              fishing_season = pop_seasons[[1]]['crab',], in_season_dpltn = TRUE, 
              fleet_size = sum(ships_per_fleet[grep('crab', names(ships_per_fleet))]), 
              fixed_costs = fixed_costs['crab'], 
              catchability = catchability['crab'], tac = NA)
sim_pars$cost_per_trip['crab'] <- exp(xx$root)

xx <- uniroot(calc_var_cost, interval = c(-20, 0),
              cost_cv = cost_cv, recruits = avg_rec['salmon'], wt_at_rec = 1, price = price['salmon'],
              fishing_season = pop_seasons[[1]]['salmon',], in_season_dpltn = TRUE, 
              fleet_size = sum(ships_per_fleet[grep('salmon', names(ships_per_fleet))]), 
              fixed_costs = fixed_costs['salmon'], catchability = catchability['salmon'], tac = salmon_tac_rule)
sim_pars$cost_per_trip['salmon'] <- exp(xx$root)

# calc_var_cost(log_avg_cost_per_trip = log(cost_per_trip['crab']),
#               cost_cv = cost_cv, recruits = 1, wt_at_rec = 1, price = 1,#c(alpha_price, beta_price),
#               fishing_season = pop_seasons[[1]]['crab',], in_season_dpltn = TRUE, fleet_size = 200,
#               fixed_costs = fixed_costs['crab'], catchability = catchability['crab'], tac = NA)

# calc_var_cost(log_avg_cost_per_trip = log(cost_per_trip['salmon']),
#               cost_cv = cost_cv, recruits = 1, wt_at_rec = 1, price = 1,#c(alpha_price, beta_price),
#               fishing_season = pop_seasons[[1]]['salmon',], in_season_dpltn = TRUE, fleet_size = 200,
#               fixed_costs = fixed_costs['salmon'], catchability = catchability['salmon'], tac = salmon_tac_rule)

# Run model! --------------------------------------------------------------

# xx <- run_sim(sim_pars = sim_pars)

# Groundfish model setup --------------------------------------------------

## Step 1: Convert VBGF * weight-length relationship to the age-weight relationship for a D-D model 
##         (based on Ford-Walford plot). Is there a rigorous way to do this? Probably makes little difference...
a.max <- 50
ages <- 1:a.max #map(1:a.max, ~ .x + 0:(wks_per_yr-1) / wks_per_yr) %>% flatten_dbl
age_at_rec <- 4
l1 <- 26
l2 <- 60
t1 <- .5
t2 <- 30
vb.k <- .37
lengths <- l1 + (l2-l1) * (1-exp(-vb.k*(ages-t1)))/(1-exp(-vb.k*(t2-t1)))
weights <- 3*10^(-6)*lengths^3.27
# recruitment to fishery at age 4
# fix weight @ recruitment to 1
rec.age.ind <- which(ages==age_at_rec)
weights <- weights/weights[rec.age.ind]
mod <- lm(weights[rec.age.ind:length(ages)] ~ weights[rec.age.ind:length(ages)-1])
growth.al <- coef(mod)[1]
growth.rho <- coef(mod)[2]
w.r <- 1
w.r.minus.1 <- (w.r - growth.al) / growth.rho
# weights.new <- numeric(length(ages) - (age_at_rec - 1)) #*wks_per_yr) # start weights.new at age 4.0
# weights.new[1] <- 1
# for(ii in 2:length(weights.new)) {
#   weights.new[ii] <- growth.al + growth.rho * weights.new[ii-1]
# }
# weights.new.yr <- weights.new[0:46 * wks_per_yr + 1]

## Step 2: Calculate S-R relationship parameters based on stock assessment assumed steepness of 0.6
M <- 0.07
# M_wk <- M/wks_per_yr
# calculate age 1+ age structure (but assume S-R relationship is for recruitment at age 0)
# age.struc <- map_dbl(1:a.max, function(.x) exp(-M * .x)) 
# age.struc[a.max] <- age.struc[a.max] / (1 - exp(-M))
# # Age 4 recruitment to fishery/spawning stock (assume same age)
# sbpr0 <- sum(age.struc[age_at_rec:a.max] * weights.new)
steepness <- 0.6
R0 <- .5
groundfish <- list(M = M, steepness = steepness, R0 = R0, alpha = growth.al, rho = growth.rho, age_at_rec = age_at_rec)

## Step 3: Reset R0 so that sustainable yield at B40% = 1
kappa <- get_kappa(groundfish = groundfish, harvest = 0, w.r = w.r, w.r.minus.1 = w.r.minus.1)
B0 <- R0 / kappa
groundfish$B0 <- B0

B40 <- .4*B0
h40 <- uniroot(solve_harvest_rate, interval = c(0,.1), target.bio = B40, groundfish = groundfish, w.r = w.r, w.r.minus.1 = w.r.minus.1)$root
R40 <- beverton_holt(B40*(1-h40), groundfish$steepness, groundfish$R0, groundfish$B0)
N40 <- R40/(1-exp(-groundfish$M)*(1-h40))

calc_groundfish_q <- function(log_q, wks_per_yr, target, nships) {
  B <- 1 # if you set B to 1 can use harvest rate as target instead of actual yield
  q <- exp(log_q)
  Catch.per.boat <- 0
  for(wk in 1:wks_per_yr){
    Catch.per.boat <- Catch.per.boat + q*B
    B <- B - nships * q * B
    if(B<=0) break
  }
  return(Catch.per.boat * nships - target)
}

xx <- uniroot(calc_groundfish_q, interval = c(log(10^(-8)), log(.01)), wks_per_yr = 40, target = h40, 
              nships = sum(ships_per_fleet[grep('groundfish', names(ships_per_fleet))]))
sim_pars$catchability['groundfish'] <- exp(xx$root)
revenue <- price['groundfish'] * h40 * B40 / 200

B <- B40
q <- sim_pars$catchability['groundfish']
Catch.per.boat <- 0
for(wk in 1:40){
  Catch.per.boat <- Catch.per.boat + q*B
  if(wk==40) min_rev <- q*B*price['groundfish']
  B <- B - nships * q * B
}

# First pass: adjust R0. 1 was just too big. Tried 0.1, seemed too small to support much revenue. Went with 0.5
# Second pass: adjust cost_per_trip. Current cost means 29% of costs are fixed costs for the fisher with average variable costs.
# I am happy with this?
# Time to run it on Monday?!?
sim_pars$cost_per_trip['groundfish'] <- 2*10^(-5)
sim_pars$fixed_costs['groundfish'] <- (revenue - qlnorm(.95, log(sim_pars$cost_per_trip['groundfish']) - cost_cv^2/2, cost_cv) * 40)

# ensure worst boat covers its variable costs so it fishes all year
min_rev > qlnorm(200/201, log(sim_pars$cost_per_trip['groundfish']) - cost_cv^2/2, cost_cv)
sim_pars$fixed_costs['groundfish']/revenue

## Step 4: Calculate variable costs! (Try to force annual harvest rate to b40.harvest by letting catchability vary?)
# xx <- uniroot(calc_var_cost_groundfish, interval = c(-20,0), cost_cv = cost_cv,
#                          fishing_season = pop_seasons[[1]]['groundfish',], bio_init = b40,
#                          N1 = N40, fleet_size = 200, in_season_dpltn = TRUE,
#                          fixed_costs = .00002, catchability = 5*10^(-6), price = 1, tac = NA, groundfish = groundfish, tol = 10^(-6))
# 
# # This function is funky. The profit at the root (profit of a marginal vessel) is always 2e-5, which is the fixed cost. This is not the case for salmon & crab. 
# # The value of the root as a function of catchability also seems oddly discountinous. You get reasonable roots at q = 5e-6 and 7e-6 but basically no fishing at 6e-6.
# 
# calc_var_cost_groundfish(log_avg_cost_per_trip = xx$root, cost_cv = cost_cv,
# fishing_season = pop_seasons[[1]]['groundfish',], bio_init = b40,
# N1 = N40, fleet_size = 200, in_season_dpltn = TRUE,
# fixed_costs = .00002, catchability = 5*10^(-6), price = 1, tac = NA, groundfish = groundfish)
# 
# b40# calc_var_cost_groundfish(log_avg_cost_per_trip = -11.9, cost_cv = cost_cv, 
#               fishing_season = pop_seasons[[1]]['groundfish',], bio_init = 1, 
#               N1 = N.seq[find_closest(bio.seq, 1)], fleet_size = 200, in_season_dpltn = TRUE, 
#               fixed_costs = .00002, catchability = 6.5*10^(-6), price = 1, tac = NA, groundfish = groundfish)
# 
# xx <- uniroot(calc_var_cost_groundfish, interval = c(-20,0), cost_cv = cost_cv, 
#               fishing_season = pop_seasons[[1]]['groundfish',], 
#               bio_init = bio.seq[find_closest(yield.seq[1:295], 0.05718231)],
#               N1 = N.seq[find_closest(yield.seq[1:295], 0.05718231)], fleet_size = 200, in_season_dpltn = TRUE, 
#               fixed_costs = .00002, catchability = 6.5*10^(-6), price = 1, tac = NA, groundfish = groundfish)

groundfish$b_init <- B40
groundfish$N_init <- N40
groundfish$rec_init <- R40
sim_pars$groundfish <- groundfish


# Beverton-Holt S-R relationship: R = a*SSB/(b+SSB)


## Good coding practices:
## a) All of this could be written to be conditional on having a stock called "groundfish"
