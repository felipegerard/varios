
# devtools::install_github("rstudio/keras")
# keras::install_keras()
# source("https://bioconductor.org/biocLite.R")
# biocLite("EBImage")

library(tidyverse)
library(magrittr)
library(jpeg)
library(EBImage)
library(keras)
library(logging)
system('set "KERAS_BACKEND=tensorflow"')
basicConfig()
setwd("~/studies/Learning/keras")

rotate_matrix <- function(x) {
  t(apply(x, 2, rev))
}


# Process data ------------------------------------------------------------


## MNIST data
mnist <- dataset_mnist()
image(rotate_matrix(mnist$train$x[3,,]))

N <- 60000
x_train <- mnist$train$x[1:N, , ] %>%
  array_reshape(c(N, prod(dim(mnist$train$x)[-1]))) %>% 
  divide_by(255)
y_train <- mnist$train$y[1:N] %>% to_categorical()

## Simpsons data
## https://www.kaggle.com/alexattia/the-simpsons-characters-dataset
# data_folder <- 'the-simpsons-characters-dataset/simpsons_dataset/simpsons_dataset/'
# images <- list.files(data_folder, full.names = TRUE, recursive = TRUE) %>% 
#   str_subset('jpg$') %>% 
#   # head(10) %>% 
#   map(function(x){
#     print(x)
#     readImage(x) %>%
#       EBImage::channel('gray') %>% 
#       EBImage::flip() %>% 
#       # array_reshape(., c(dim(.)[1:3])) %>%
#       EBImage::resize(w = 100, h = 100)
#   })
# # simpsons_data <- reduce(images, abind::abind, along = 3)
# vectors <- images %>% 
#   map(as.numeric)
# simpsons_data <- do.call(rbind, vectors)
# 
# if (FALSE) {
#   saveRDS(simpsons_data, 'data/simpsons_data.rds')
#   rm(images, vectors, simpsons_data)
# }
x_train <- readRDS('data/simpsons_data.rds')




# Network-generating functions --------------------------------------------


get_optimizer <- function() {
  optimizer_adam(lr = 0.0002, beta_1 = 0.5)
}

get_generator <- function(optimizer, input_shape) {
  keras_model_sequential() %>% 
    layer_dense(256,
                input_shape = input_shape,
                kernel_initializer =initializer_random_normal(stddev = 0.02)) %>% 
    layer_activation_leaky_relu(0.2) %>% 
    layer_dense(512) %>% 
    layer_activation_leaky_relu(0.2) %>% 
    layer_dense(256) %>% 
    layer_activation_leaky_relu(0.2) %>% 
    layer_dense(dim(x_train)[2], activation = 'tanh') %>% 
    compile(loss = 'binary_crossentropy', optimizer = optimizer)
}

get_discriminator <- function(optimizer) {
  keras_model_sequential() %>% 
    layer_dense(1024,
                input_shape = dim(x_train)[2],
                kernel_initializer =initializer_random_normal(stddev = 0.02)) %>% 
    layer_activation_leaky_relu(0.2) %>% 
    layer_dropout(0.3) %>% 
    layer_dense(512) %>% 
    layer_activation_leaky_relu(0.2) %>% 
    layer_dropout(0.3) %>% 
    layer_dense(256) %>% 
    layer_activation_leaky_relu(0.2) %>% 
    layer_dropout(0.3) %>% 
    layer_dense(1, activation = 'sigmoid') %>% 
    compile(loss = 'binary_crossentropy', optimizer = optimizer)
}

get_gan_network <- function(discriminator, random_shape, generator, optimizer) {
  discriminator$trainable <- FALSE
  gan_input <- layer_input(shape = random_shape)
  x <- generator(gan_input)
  gan_output <- discriminator(x)
  keras_model(inputs = gan_input, outputs = gan_output) %>% 
    compile(loss = 'binary_crossentropy', optimizer = optimizer)
}

plot_generated_images <- function(epoch, generator, random_shape, examples = 15) {
  noise <- matrix(rnorm(examples * random_shape), nrow = examples, ncol = random_shape)
  generated_images <- predict(generator, noise) %>% array_reshape(., c(dim(.)[1], sqrt(ncol(.)), sqrt(ncol(.))))
  generated_images <- (1 - generated_images) / 2
  col <- gray.colors(1000, 0, 1)
  layout(matrix(1:examples, nrow = floor(sqrt(examples))))
  for (i in seq_len(nrow(generated_images))) {
    image(rotate_matrix(generated_images[i, , ]), axes = FALSE, col = col, asp = 1)
  }
}

train_gan <- function(generator, discriminator, gan, epochs = 1, batch_size = 128, random_shape = 100, verbose_iter = 20, examples = 15) {
  batch_count <- round(nrow(x_train) / batch_size)
  pb <- txtProgressBar(0, batch_count, style = 3)
  for (e in seq_len(epochs)) {
    loginfo(sprintf('Epoch: %d', e))
    for (k in 1:batch_count){
      # Get a random set of input noise and images
      noise <- matrix(rnorm(batch_size * random_shape), nrow = batch_size, ncol = random_shape)
      image_batch <- x_train[sample(seq_len(nrow(x_train)), size = batch_size), ]
      
      # Generate fake images
      generated_images <- predict(generator, noise)
      X <- rbind(image_batch, generated_images)
      
      # Labels for generated and real data
      y_dis <- rep(0, 2 * batch_size)
      # One-sided label smoothing
      y_dis[1:batch_size] <- 0.9
      
      # Train discriminator
      discriminator$trainable <- TRUE
      train_on_batch(discriminator, X, y_dis)
      
      # Train generator
      noise <- matrix(rnorm(batch_size * random_shape), nrow = batch_size, ncol = random_shape)
      y_gen <- rep(1, batch_size)
      discriminator$trainable <- FALSE
      train_on_batch(gan, noise, y_gen)
      setTxtProgressBar(pb, k)
    }
    if (e == 1 || e %% verbose_iter == 0) {
       plt <- safely(plot_generated_images)(e, generator, random_shape, examples = examples)
       if (!is.null(plt$error)) {
         logwarn('Something went wrong with the plots. Resetting device...')
         dev.off()
       }
    }
  }
  list(generator = generator, discriminator = discriminator, gan = gan)
}



# Train network -----------------------------------------------------------

adam <- get_optimizer()
generator <- get_generator(adam, random_shape)
discriminator <- get_discriminator(adam)
gan <- get_gan_network(discriminator, random_shape, generator, adam)

out <- train_gan(
  generator = generator,
  discriminator = discriminator,
  gan = gan,
  epochs = 100,
  batch_size = 128,
  random_shape = 200,
  verbose_iter = 3,
  examples = 15
)


# plot_generated_images(1, out$generator, 200, 15)


## Train some more
out <- train_gan(
  generator = out$generator,
  discriminator = out$discriminator,
  gan = out$gan,
  epochs = 100,
  batch_size = 128,
  random_shape = 200,
  verbose_iter = 3,
  examples = 15
)


#' TO DO
#' * Try applying some smoothing/pooling/convolution
#' * Try having bigger layers
















