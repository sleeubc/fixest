#----------------------------------------------#
# Author: Laurent Berge
# Date creation: Fri Jul 10 09:03:06 2020
# ~: package sniff tests
#----------------------------------------------#

# Not all functionnalities are currenlty covered, but I'll improve it over time
# I should migrate and clean the code from _CHECK_PACKAGE.R

# Some functions are not trivial to test properly though

####
#### Estimations ####
####

cat("ESTIMATION\n\n")


base = iris
names(base) = c("y", "x1", "x2", "x3", "species")
base$fe_2 = sample(5, nrow(base), TRUE)
base$constant = 5
base$y_int = as.integer(base$y)
base$w = as.vector(unclass(base$species) - 0.95)
base$offset = unclass(base$species) - 0.95
base$y_01 = as.vector(1 * ((scale(base$x1)+rnorm(150)) > 0))

for(model in c("ols", "pois", "logit", "negbin", "Gamma")){
    cat("Model: ", sfill(model, 6), sep = "")
    for(use_weights in c(FALSE, TRUE)){
        my_weight = NULL
        if(use_weights) my_weight = base$w

        for(use_offset in c(FALSE, TRUE)){
            my_offset = NULL
            if(use_offset) my_offset = base$offset

            for(nb_fe in 0:7){

                cat(".")

                tol  = ifelse(model == "negbin", 1e-2, 1e-5)

                # Setting up the formula to accomodate FEs
                if(nb_fe == 0){
                    fml_fixest = fml_stats = y ~ x1
                } else if(nb_fe == 1){
                    fml_fixest = y ~ x1 | species
                    fml_stats = y ~ x1 + factor(species)
                } else if(nb_fe == 2){
                    fml_fixest = y ~ x1 | species + fe_2
                    fml_stats = y ~ x1 + factor(species) + factor(fe_2)
                } else if(nb_fe == 3){
                    # varying slope
                    fml_fixest = y ~ x1 | species[[x2]]
                    fml_stats = y ~ x1 + x2:species
                } else if(nb_fe == 4){
                    # varying slope -- 1 VS, 1 FE
                    fml_fixest = y ~ x1 | species[[x2]] + fe_2
                    fml_stats = y ~ x1 + x2:species + factor(fe_2)
                } else if(nb_fe == 5){
                    # varying slope -- 2 VS
                    fml_fixest = y ~ x1 | species[x2]
                    fml_stats = y ~ x1 + x2:species + species
                } else if(nb_fe == 6){
                    # varying slope -- 2 VS bis
                    fml_fixest = y ~ x1 | species[[x2]] + fe_2[[x3]]
                    fml_stats = y ~ x1 + x2:species + x3:factor(fe_2)
                } else if(nb_fe == 7){
                    # Combnined clusters
                    fml_fixest = y ~ x1 + x2 | species^fe_2
                    fml_stats = y ~ x1 + x2 + paste(species, fe_2)
                } else if(nb_fe == Inf){
                    # Lots of FEs => I'll check that when the VS problem is fixed
                    fml_fixest = y ~ x1 | species[x2] + fe_2[x3]
                    fml_stats = y ~ x1 + x2:species + x3:factor(fe_2) + species + factor(fe_2)
                }

                # ad hoc modifications of the formula
                if(model == "logit"){
                    fml_fixest = update(Formula(fml_fixest), y_01 ~.)
                    fml_stats = update(fml_stats, y_01 ~.)
                } else if(model %in% c("pois", "negbin", "Gamma")){
                    fml_fixest = update(Formula(fml_fixest), y_int ~.)
                    fml_stats = update(fml_stats, y_int ~.)
                }

                adj = 1
                if(model == "ols"){
                    res = feols(fml_fixest, base, weights = my_weight, offset = my_offset)
                    res_bis = lm(fml_stats, base, weights = my_weight, offset = my_offset)

                } else if(model %in% c("pois", "logit", "Gamma")){
                    adj = 0
                    if(model == "Gamma" && use_offset) next

                    my_family = switch(model, pois = poisson(), logit = binomial(), Gamma = Gamma())

                    res =  feglm(fml_fixest, base, family = my_family, weights = my_weight, offset = my_offset)
                    res_bis = glm(fml_stats, base, family = my_family, weights = my_weight, offset = my_offset)

                } else if(model == "negbin"){
                    # no offset in glm.nb + no VS in fenegbin + no weights in fenegbin
                    if(use_weights || use_offset || nb_fe > 2) next

                    res = fenegbin(fml_fixest, base, notes = FALSE)
                    res_bis = MASS::glm.nb(fml_stats, base)

                }

                test(coef(res)["x1"], coef(res_bis)["x1"], "~", tol)
                test(se(res, se = "st", dof = dof(adj = adj))["x1"], se(res_bis)["x1"], "~", tol)
                test(pvalue(res, se = "st", dof = dof(adj = adj))["x1"], pvalue(res_bis)["x1"], "~", tol*10**(model == "negbin"))
                # cat("Model: ", model, ", FE: ", nb_fe, ", weight: ", use_weights,  ", offset: ", use_offset, "\n", sep="")

            }
            cat("|")
        }
    }
    cat("\n")
}

####
#### Standard-errors ####
####

cat("STANDARD ERRORS\n\n")

#
# Fixed-effects corrections
#

# We create "irregular" FEs
set.seed(0)
base = data.frame(x = rnorm(20))
base$y = base$x + rnorm(20)
base$fe1 = rep(rep(1:3, c(4, 3, 3)), 2)
base$fe2 = rep(rep(1:5, each = 2), 2)
est = feols(y ~ x | fe1 + fe2, base)

# fe1: 3 FEs
# fe2: 5 FEs

#
# Clustered standard-errors: by fe1
#

# Default: fixef.K = "nested"
#  => adjustment K = 1 + 5 (i.e. x + fe2)
test(attr(vcov(est, dof = dof(fixef.K = "nested")), "dof.K"), 6)

# fixef.K = FALSE
#  => adjustment K = 1 (i.e. only x)
test(attr(vcov(est, dof = dof(fixef.K = "none")), "dof.K"), 1)

# fixef.K = TRUE
#  => adjustment K = 1 + 3 + 5 - 1 (i.e. x + fe1 + fe2 - 1 restriction)
test(attr(vcov(est, dof = dof(fixef.K = "full")), "dof.K"), 8)

# fixef.K = TRUE & fixef.exact = TRUE
#  => adjustment K = 1 + 3 + 5 - 2 (i.e. x + fe1 + fe2 - 2 restrictions)
test(attr(vcov(est, dof = dof(fixef.K = "full", fixef.force_exact = TRUE)), "dof.K"), 7)

#
# Manual checks of the SEs
#

n = est$nobs
VCOV_raw = est$cov.unscaled / ((n - 1) / (n - est$nparams))

# standard
for(k_val in c("none", "nested", "full")){
    for(adj in c(FALSE, TRUE)){

        K = switch(k_val, none = 1, nested = 8, full = 8)
        my_adj = ifelse(adj, (n - 1) / (n - K), 1)

        test(vcov(est, se = "standard", dof = dof(adj = adj, fixef.K = k_val)), VCOV_raw * my_adj)

        # cat("adj = ", adj, " ; fixef.K = ", k_val, "\n", sep = "")
    }
}

# Clustered, fe1
VCOV_raw = est$cov.unscaled / est$sigma2
H = vcovClust(est$fixef_id$fe1, VCOV_raw, scores = est$scores, dof = FALSE)

for(tdf in c("conventional", "min")){
    for(k_val in c("none", "nested", "full")){
        for(c_adj in c(FALSE, TRUE)){
            for(adj in c(FALSE, TRUE))

                K = switch(k_val, none = 1, nested = 6, full = 8)
            cluster_factor = ifelse(c_adj, 3/2, 1)
            df = ifelse(tdf == "min", 2, 20 - 8)
            my_adj = ifelse(adj, (n - 1) / (n - K), 1)

            V = H * cluster_factor

            # test SE
            test(vcov(est, se = "cluster", dof = dof(adj = adj, fixef.K = k_val, cluster.adj = c_adj)), V * my_adj)

            # test pvalue
            my_tstat = tstat(est, se = "cluster", dof = dof(adj = adj, fixef.K = k_val, cluster.adj = c_adj))
            test(pvalue(est, se = "cluster", dof = dof(adj = adj, fixef.K = k_val, cluster.adj = c_adj, t.df = tdf)), 2*pt(-abs(my_tstat), df))

            # cat("adj = ", adj, " ; fixef.K = ", k_val, " ; cluster.adj = ", c_adj, " t.df = ", tdf, "\n", sep = "")
        }
    }
}


# 2-way Clustered, fe1 fe2
VCOV_raw = est$cov.unscaled / est$sigma2
M_i  = vcovClust(est$fixef_id$fe1, VCOV_raw, scores = est$scores, dof = FALSE)
M_t  = vcovClust(est$fixef_id$fe2, VCOV_raw, scores = est$scores, dof = FALSE)
M_it = vcovClust(paste(base$fe1, base$fe2), VCOV_raw, scores = est$scores, dof = FALSE, do.unclass = TRUE)

M_i + M_t - M_it
vcov(est, se = "two", dof = dof(adj = FALSE, cluster.adj = FALSE))

for(cdf in c("conventional", "min")){
    for(tdf in c("conventional", "min")){
        for(k_val in c("none", "nested", "full")){
            for(c_adj in c(FALSE, TRUE)){
                for(adj in c(FALSE, TRUE)){

                    K = switch(k_val, none = 1, nested = 2, full = 8)

                    if(c_adj){
                        if(cdf == "min"){
                            V = (M_i + M_t - M_it) * 3/2
                        } else {
                            V = M_i  * 3/2 + M_t * 5/4 - M_it * 6/5
                        }
                    } else {
                        V = M_i + M_t - M_it
                    }

                    df = ifelse(tdf == "min", 2, 20 - 8)
                    my_adj = ifelse(adj, (n - 1) / (n - K), 1)

                    # test SE
                    test(vcov(est, se = "two", dof = dof(adj = adj, fixef.K = k_val, cluster.adj = c_adj, cluster.df = cdf)),
                         V * my_adj)

                    # test pvalue
                    my_tstat = tstat(est, se = "two", dof = dof(adj = adj, fixef.K = k_val, cluster.adj = c_adj, cluster.df = cdf))
                    test(pvalue(est, se = "two", dof = dof(adj = adj, fixef.K = k_val, cluster.adj = c_adj, cluster.df = cdf, t.df = tdf)),
                         2*pt(-abs(my_tstat), df))

                    # cat("adj = ", adj, " ; fixef.K = ", k_val, " ; cluster.adj = ", c_adj, " t.df = ", tdf, "\n", sep = "")
                }
            }
        }
    }
}


#
# Comparison with sandwich and plm
#

library(sandwich)

# Data generation
set.seed(0)
N <- 20; G <- N/5; T <- N/G
d <- data.frame( y=rnorm(N), x=rnorm(N), grp=rep(1:G,T), tm=rep(1:T,each=G) )

# Estimations
est_lm    = lm(y ~ x + as.factor(grp) + as.factor(tm), data=d)
est_feols = feols(y ~ x | grp + tm, data=d)

#
# Standard
#

test(se(est_feols, se = "st")["x"], se(est_lm)["x"])

#
# Clustered
#

# Clustered by grp
se_CL_grp_lm_HC1 = sqrt(vcovCL(est_lm, cluster = d$grp, type = "HC1")["x", "x"])
se_CL_grp_lm_HC0 = sqrt(vcovCL(est_lm, cluster = d$grp, type = "HC0")["x", "x"])
se_CL_grp_stata  = 0.165385 # vce(cluster grp)

# How to get the lm
test(se(est_feols, dof = dof(fixef.K = "full")), se_CL_grp_lm_HC1)
test(se(est_feols, dof = dof(adj = FALSE, fixef.K = "full")), se_CL_grp_lm_HC0)

# How to get the Stata
test(se(est_feols), se_CL_grp_stata, "~")

#
# White
#

se_white_lm_HC1 = sqrt(vcovHC(est_lm, type = "HC1")["x", "x"])
se_white_lm_HC0 = sqrt(vcovHC(est_lm, type = "HC0")["x", "x"])

test(se(est_feols, se = "white"), se_white_lm_HC1)
test(se(est_feols, se = "white", dof = dof(adj = FALSE, cluster.adj = FALSE)), se_white_lm_HC0)

#
# Two way
#

# Clustered by grp & tm
se_CL_2w_lm    = sqrt(vcovCL(est_lm, cluster = ~ grp + tm, type = "HC1")["x", "x"])
se_CL_2w_feols = se(est_feols, se = "twoway")

test(se(est_feols, se = "twoway", dof = dof(fixef.K = "full")), se_CL_2w_lm)

#
# Checking the calls work properly
#

data(trade)

est_pois = femlm(Euros ~ log(dist_km)|Origin+Destination, trade)

se_clust = se(est_pois, se = "cluster", cluster = "Product")
test(se(est_pois, cluster = trade$Product), se_clust)
test(se(est_pois, cluster = ~Product), se_clust)

se_two = se(est_pois, se = "twoway", cluster = trade[, c("Product", "Destination")])
test(se_two, se(est_pois, cluster = c("Product", "Destination")))
test(se_two, se(est_pois, cluster = ~Product+Destination))

se_clu_comb = se(est_pois, cluster = "Product^Destination")
test(se_clu_comb, se(est_pois, cluster = paste(trade$Product, trade$Destination)))
test(se_clu_comb, se(est_pois, cluster = ~Product^Destination))

se_two_comb = se(est_pois, cluster = c("Origin^Destination", "Product"))
test(se_two_comb, se(est_pois, cluster = list(paste(trade$Origin, trade$Destination), trade$Product)))
test(se_two_comb, se(est_pois, cluster = ~Origin^Destination + Product))

# With cluster removed
base = trade
base$Euros[base$Origin == "FR"] = 0
est_pois = femlm(Euros ~ log(dist_km)|Origin+Destination, base)

se_clust = se(est_pois, se = "cluster", cluster = "Product")
test(se(est_pois, cluster = base$Product), se_clust)
test(se(est_pois, cluster = ~Product), se_clust)

se_two = se(est_pois, se = "twoway", cluster = base[, c("Product", "Destination")])
test(se_two, se(est_pois, cluster = c("Product", "Destination")))
test(se_two, se(est_pois, cluster = ~Product+Destination))

se_clu_comb = se(est_pois, cluster = "Product^Destination")
test(se_clu_comb, se(est_pois, cluster = paste(base$Product, base$Destination)))
test(se_clu_comb, se(est_pois, cluster = ~Product^Destination))

se_two_comb = se(est_pois, cluster = c("Origin^Destination", "Product"))
test(se_two_comb, se(est_pois, cluster = list(paste(base$Origin, base$Destination), base$Product)))
test(se_two_comb, se(est_pois, cluster = ~Origin^Destination + Product))

# With cluster removed and NAs
base = trade
base$Euros[base$Origin == "FR"] = 0
base$Euros_na = base$Euros ; base$Euros_na[sample(nrow(base), 50)] = NA
base$Destination_na = base$Destination ; base$Destination_na[sample(nrow(base), 50)] = NA
base$Origin_na = base$Origin ; base$Origin_na[sample(nrow(base), 50)] = NA
base$Product_na = base$Product ; base$Product_na[sample(nrow(base), 50)] = NA

est_pois = femlm(Euros ~ log(dist_km)|Origin+Destination_na, base)

se_clust = se(est_pois, se = "cluster", cluster = "Product")
test(se(est_pois, cluster = base$Product), se_clust)
test(se(est_pois, cluster = ~Product), se_clust)

se_two = se(est_pois, se = "twoway", cluster = base[, c("Product", "Destination")])
test(se_two, se(est_pois, cluster = c("Product", "Destination")))
test(se_two, se(est_pois, cluster = ~Product+Destination))

se_clu_comb = se(est_pois, cluster = "Product^Destination")
test(se_clu_comb, se(est_pois, cluster = paste(base$Product, base$Destination)))
test(se_clu_comb, se(est_pois, cluster = ~Product^Destination))

se_two_comb = se(est_pois, cluster = c("Origin^Destination", "Product"))
test(se_two_comb, se(est_pois, cluster = list(paste(base$Origin, base$Destination), base$Product)))
test(se_two_comb, se(est_pois, cluster = ~Origin^Destination + Product))

#
# Checking errors
#

# Should report error
test(se(est_pois, cluster = "Origin_na"), "err")
test(se(est_pois, cluster = base$Origin_na), "err")
test(se(est_pois, cluster = list(base$Origin_na)), "err")
test(se(est_pois, cluster = ~Origin_na^Destination), "err")

test(se(est_pois, se = "cluster", cluster = ~Origin_na^not_there), "err")

test(se(est_pois, se = "twoway", cluster = c("Origin^Destination", "Product", "error")), "err")
test(se(est_pois, se = "twoway", cluster = base[, 1:4]), "err")
test(se(est_pois, se = "twoway", cluster = ~Origin+Destination+Product), "err")
test(se(est_pois, se = "fourway", cluster = ~Origin+Destination+Product), "err")

####
#### Residuals ####
####

cat("RESIDUALS\n\n")

base = iris
names(base) = c("y", "x1", "x2", "x3", "species")
base$y_int = as.integer(base$y) + 1

# OLS + GLM + FENMLM

for(method in c("ols", "feglm", "femlm", "fenegbin")){
    cat("Method: ", sfill(method, 8))
    for(do_weight in c(FALSE, TRUE)){
        cat(".")

        if(do_weight){
            w = unclass(as.factor(base$species))
        } else {
            w = NULL
        }

        if(method == "ols"){
            m = feols(y_int ~ x1 | species, base, weights = w)
            mm = lm(y_int ~ x1 + species, base, weights = w)

        } else if(method == "feglm"){
            m = feglm(y_int ~ x1 | species, base, weights = w)
            mm = glm(y_int ~ x1 + species, base, weights = w, family = poisson())

        } else if(method == "femlm"){
            if(!is.null(w)) next
            m = femlm(y_int ~ x1 | species, base)
            mm = glm(y_int ~ x1 + species, base, family = poisson())

        } else if(method == "fenegbin"){
            if(!is.null(w)) next
            m = fenegbin(y_int ~ x1 | species, base, notes = FALSE)
            mm = MASS::glm.nb(y_int ~ x1 + species, base)
        }

        tol = ifelse(method == "fenegbin", 1e-2, 1e-6)

        test(resid(m, "r"), resid(mm, "resp"), "~", tol = tol)
        test(resid(m, "d"), resid(mm, "d"), "~", tol = tol)
        test(resid(m, "p"), resid(mm, "pearson"), "~", tol = tol)

        test(deviance(m), deviance(mm), "~", tol = tol)
    }
    cat("\n")
}
cat("\n")



####
#### To Integer ####
####

cat("TO_INTEGER\n\n")

base = iris
names(base) = c("y", "x1", "x2", "x3", "species")
base$z = sample(5, 150, TRUE)

# Normal
m = to_integer(base$species)
test(length(unique(m)), 3)

m = to_integer(base$species, base$z)
test(length(unique(m)), 15)

# with NA
base$species_na = base$species
base$species_na[base$species == "setosa"] = NA

m = to_integer(base$species_na, base$z)
test(length(unique(m)), 11)

m = to_integer(base$species_na, base$z, add_items = TRUE, items.list = TRUE)
test(length(m$items), 10)


####
#### Collinearity ####
####

cat("COLLINEARITY\n\n")

base = iris
names(base) = c("y", "x1", "x2", "x3", "species")
base$constant = 5
base$y_int = as.integer(base$y)
base$w = as.vector(unclass(base$species) - 0.95)

setFixest_notes(FALSE)

for(useWeights in c(FALSE, TRUE)){
    for(model in c("ols", "pois")){
        for(use_fe in c(FALSE, TRUE)){
            cat(".")

            my_weight = NULL
            if(useWeights) my_weight = base$w

            adj = 1
            if(model == "ols"){
                if(!use_fe){
                    res = feols(y ~ x1 + constant, base, weights = my_weight)
                    res_bis = lm(y ~ x1 + constant, base, weights = my_weight)
                } else {
                    res = feols(y ~ x1 + constant | species, base, weights = my_weight)
                    res_bis = lm(y ~ x1 + constant + species, base, weights = my_weight)
                }
            } else {
                if(!use_fe){
                    res = fepois(y_int ~ x1 + constant, base, weights = my_weight)
                    res_bis = glm(y_int ~ x1 + constant, base, weights = my_weight, family = poisson)
                } else {
                    res = fepois(y_int ~ x1 + constant | species, base, weights = my_weight)
                    res_bis = glm(y_int ~ x1 + constant + species, base, weights = my_weight, family = poisson)
                }
                adj = 0
            }

            test(coef(res)["x1"], coef(res_bis)["x1"], "~")
            test(se(res, se = "st", dof = dof(adj=adj))["x1"], se(res_bis)["x1"], "~")
            # cat("Weight: ", useWeights, ", model: ", model, ", FE: ", use_fe, "\n", sep="")

        }
    }
}
cat("\n")



####
#### demean ####
####

cat("DEMEAN\n\n")

data(trade)

base = trade
base$ln_euros = log(base$Euros)
base$ln_dist = log(base$dist_km)

X = base[, c("ln_euros", "ln_dist")]
fe = base[, c("Origin", "Destination")]

X_demean = demean(X, fe)
base_new = as.data.frame(X_demean)

a = feols(ln_euros ~ ln_dist, base_new)
b = feols(ln_euros ~ ln_dist | Origin + Destination, base, demeaned = TRUE)

test(coef(a)[-1], coef(b), "~", 1e-12)

test(X_demean[, 1], b$y_demeaned)
test(X_demean[, -1], b$X_demeaned)

# NAs
X_NA = X
fe_NA =fe
X_NA[sample(nrow(X_NA), 50), 1] = NA
fe_NA[sample(nrow(fe_NA), 50), 1] = NA
X_demean = demean(X_NA, fe_NA)


####
#### hatvalues ####
####


cat("HATVALUES\n\n")


x = sin(1:10)
y = rnorm(10)
y_int = rpois(10, 2)
fm  = lm(y ~ x)
ffm = feols(y ~ x, data.frame(y, x))

test(hatvalues(ffm), hatvalues(fm))

gm  = glm(y_int ~ x, family = poisson())
fgm = fepois(y_int ~ x, data.frame(y_int, x))

test(hatvalues(fgm), hatvalues(gm))


####
#### sandwich ####
####

cat("SANDWICH\n\n")

# Compatibility with sandwich

library(sandwich)

data(base_did)
est = feols(y ~ x1 + I(x1**2) + factor(id), base_did)

test(vcov(est, cluster = ~id), vcovCL(est, cluster = ~id, type = "HC1"))

est_pois = fepois(as.integer(y) + 20 ~ x1 + I(x1**2) + factor(id), base_did)

test(vcov(est_pois, cluster = ~id), vcovCL(est_pois, cluster = ~id, type = "HC1"))

# With FEs

est = feols(y ~ x1 + I(x1**2) | id, base_did)

test(vcov(est, cluster = ~id, dof = dof(adj = FALSE)), vcovCL(est, cluster = ~id))

est_pois = fepois(as.integer(y) + 20 ~ x1 + I(x1**2) | id, base_did)

test(vcov(est_pois, cluster = ~id, dof = dof(adj = FALSE)), vcovCL(est_pois, cluster = ~id))








